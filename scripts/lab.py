#!/usr/bin/env python3
"""Small AWS CLI lifecycle. Plan by default; never logs identity/IP/key payloads."""
import argparse
import base64
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import ssl
import stat
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REGION = "ap-northeast-2"
MISSING = {
    "describe-vpcs": {"InvalidVpcID.NotFound"},
    "describe-subnets": {"InvalidSubnetID.NotFound"},
    "describe-internet-gateways": {"InvalidInternetGatewayID.NotFound"},
    "describe-route-tables": {"InvalidRouteTableID.NotFound"},
    "describe-security-groups": {"InvalidGroup.NotFound"},
    "describe-key-pairs": {"InvalidKeyPair.NotFound", "InvalidKeyPairID.NotFound"},
    "describe-instances": {"InvalidInstanceID.NotFound"},
    "describe-volumes": {"InvalidVolume.NotFound"},
    "describe-network-interfaces": {"InvalidNetworkInterfaceID.NotFound"},
}
SPEC = {
    "vpc": ("describe-vpcs", "--vpc-ids", "Vpcs", "vpc"),
    "subnet": ("describe-subnets", "--subnet-ids", "Subnets", "subnet"),
    "igw": ("describe-internet-gateways", "--internet-gateway-ids", "InternetGateways", "igw"),
    "rt": ("describe-route-tables", "--route-table-ids", "RouteTables", "rtb"),
    "sg": ("describe-security-groups", "--group-ids", "SecurityGroups", "sg"),
    "key": ("describe-key-pairs", "--key-pair-ids", "KeyPairs", "key"),
    "instance": ("describe-instances", "--instance-ids", "Reservations", "i"),
    "volume": ("describe-volumes", "--volume-ids", "Volumes", "vol"),
    "eni": ("describe-network-interfaces", "--network-interface-ids", "NetworkInterfaces", "eni"),
}


class LabError(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise LabError(reason)


def secure_path(path, base):
    path = Path(path).absolute()
    require(".." not in path.parts, "PATH_TRAVERSAL_FORBIDDEN")
    require(path.is_relative_to(base.absolute()), "PATH_OUTSIDE_ALLOWED_DIRECTORY")
    for component in [path, *path.parents]:
        require(not component.is_symlink(), "SYMLINK_FORBIDDEN")
    return path


def atomic_state(path, data, create_only=False):
    path = secure_path(path, ROOT / "runtime")
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.exists():
        s = path.stat()
        require(stat.S_ISREG(s.st_mode) and s.st_uid == os.getuid()
                and stat.S_IMODE(s.st_mode) == 0o600, "INSECURE_STATE_FILE")
    temporary = path.parent / (".state-" + secrets.token_hex(12))
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        if create_only:
            os.link(temporary, path, follow_symlinks=False)
            temporary.unlink()
        else:
            os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if temporary.exists():
            temporary.unlink()


def account_binding(salt, account):
    return hashlib.sha256((salt + ":" + account).encode()).hexdigest()


class AWS:
    def __init__(self, profile, region, runner=subprocess.run):
        self.profile, self.region, self.runner = profile, region, runner
        self.events = []

    def raw(self, service, operation, args, payload=None):
        if payload is not None:
            args = [*args, "--cli-input-json", "file:///dev/stdin"]
        return self.runner(["aws", service, operation, "--profile", self.profile,
                            "--region", self.region, "--output", "json", "--no-cli-pager", *args],
                           capture_output=True, text=True, **({"input": json.dumps(payload)} if payload is not None else {}))

    def call(self, operation, args=(), *, service="ec2", absent=False, dry=False, payload=None):
        result = self.raw(service, operation, list(args), payload)
        match = re.search(r"\(([^)]+)\)", result.stderr)
        code = match.group(1) if match else "CLI_ERROR_OR_LOGIN_REQUIRED"
        self.events.append({"operation": operation, "exit_code": result.returncode,
                            "error_code": code if result.returncode else None})
        if dry:
            require(result.returncode != 0 and code == "DryRunOperation", "DRY_RUN_NOT_AUTHORIZED:" + code)
            return None
        if result.returncode:
            if absent and code in MISSING.get(operation, set()):
                return None
            raise LabError("API_FAILED_NOT_ABSENCE:" + operation + ":" + code)
        try:
            return json.loads(result.stdout) if result.stdout.strip() else {}
        except (ValueError, TypeError):
            raise LabError("UNPARSEABLE_API_RESPONSE:" + operation) from None


def persist_key_response(raw, fd, write=os.write, fsync=os.fsync, wait=time.sleep):
    """Material lives in memory until the exclusive file is durable; no optional-field assumptions."""
    try:
        response = json.loads(raw)
        material = response.get("KeyMaterial")
        require(isinstance(material, str) and bool(material), "MISSING_KEY_MATERIAL")
        payload = material.encode()
    except Exception:
        print("KEY_RESULT_UNKNOWN_RESPONSE_RETAINED_IN_MEMORY_NO_RECREATE", flush=True)
        while True:
            wait(5)  # operator must reconcile; never print raw response or issue another create
    offset = 0
    while offset < len(payload):
        try:
            count = write(fd, payload[offset:])
            if count <= 0:
                raise OSError("zero write")
            offset += count
        except InterruptedError:
            continue
        except OSError:
            print("KEY_WRITE_BLOCKED_MATERIAL_RETAINED_IN_MEMORY", flush=True)
            wait(1)
    while True:
        try:
            fsync(fd)
            break
        except InterruptedError:
            continue
        except OSError:
            print("KEY_FSYNC_BLOCKED_MATERIAL_RETAINED_IN_MEMORY", flush=True)
            wait(1)
    return {"id": response.get("KeyPairId"), "fingerprint": response.get("KeyFingerprint")}


def source_ipv4():
    require(not any(os.environ.get(k) for k in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
                                               "http_proxy", "https_proxy", "all_proxy")),
            "PROXY_ENVIRONMENT_REQUIRES_OPERATOR_REVIEW")
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                        urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    with opener.open("https://checkip.amazonaws.com", timeout=15) as response:
        address = ipaddress.ip_address(response.read(128).decode().strip())
    require(address.version == 4 and address.is_global, "GLOBAL_IPV4_REQUIRED")
    return str(address)


class Lab:
    def __init__(self, args, aws=None, ip_lookup=source_ipv4, sleeper=time.sleep):
        require(not sys.flags.optimize, "OPTIMIZED_INTERPRETER_FORBIDDEN")
        require(args.region == REGION, "SEOUL_REGION_REQUIRED")
        require(re.fullmatch(r"[0-9]{12}", args.expected_account or ""), "EXPECTED_ACCOUNT_12_DIGITS_REQUIRED")
        require(re.fullmatch(r"[A-Za-z0-9_+=,.@-]{1,64}", args.iam_user or ""), "EXPECTED_IAM_USER_REQUIRED")
        self.args, self.aws, self.ip_lookup, self.sleep = args, aws or AWS(args.profile, args.region), ip_lookup, sleeper
        self.path = secure_path(args.state, ROOT / "runtime")
        self.state = None
        self.state_owned = self.path.exists()
        if self.path.exists():
            s = self.path.stat()
            require(stat.S_ISREG(s.st_mode) and s.st_uid == os.getuid()
                    and stat.S_IMODE(s.st_mode) == 0o600, "INSECURE_STATE_FILE")
            self.state = json.loads(self.path.read_text())
            self.validate_state()
            self.aws.events = list(self.state.get("events", []))

    def validate_state(self):
        s = self.state
        require(s.get("schema") == 1 and s.get("region") == REGION
                and s.get("profile") == self.args.profile, "STATE_CONTEXT_MISMATCH")
        require(s.get("account_binding") == account_binding(s.get("account_salt", ""), self.args.expected_account),
                "STATE_ACCOUNT_MISMATCH")
        require(s.get("iam_user") == self.args.iam_user, "STATE_PRINCIPAL_MISMATCH")
        require(re.fullmatch(r"[a-z0-9][a-z0-9-]{2,30}", s.get("run_id", "")), "INVALID_RUN_ID")
        require(s.get("status") in ("CREATING", "ACTIVE", "DESTROYING", "DESTROYED", "UNKNOWN"), "INVALID_STATE_STATUS")
        require(not s.get("historical_closed") or s["status"] == "DESTROYED", "HISTORICAL_STATE_READ_ONLY")
        for kind, ident in s.get("refs", {}).items():
            prefix = SPEC[kind][3] if kind in SPEC else "rtbassoc" if kind == "assoc" else None
            require(prefix and re.fullmatch(prefix + r"-[0-9a-f]{8,17}", ident), "INVALID_TYPED_RESOURCE_ID")

    def identity(self):
        d = self.aws.call("get-caller-identity", service="sts")
        require(d.get("Account") == self.args.expected_account and
                d.get("Arn") == "arn:aws:iam::" + self.args.expected_account + ":user/" + self.args.iam_user,
                "WRONG_ACCOUNT_OR_NON_IAM_USER")

    def save(self):
        self.state["events"] = self.aws.events
        atomic_state(self.path, self.state, create_only=not self.state_owned)
        self.state_owned = True

    def tags(self, kind):
        return [{"Key": "Project", "Value": "B6-1"},
                {"Key": "RunId", "Value": self.state["run_id"]},
                {"Key": "Name", "Value": "b6-1-" + self.state["run_id"] + "-" + kind}]

    def tag_spec(self, resource, kind):
        return ["--tag-specifications", json.dumps([{"ResourceType": resource, "Tags": self.tags(kind)}])]

    def own(self, resource, kind):
        require(all(t in resource.get("Tags", []) for t in self.tags(kind)), "RESOURCE_RUN_TAG_MISMATCH")
        if "OwnerId" in resource:
            require(resource["OwnerId"] == self.args.expected_account, "RESOURCE_OWNER_MISMATCH")

    def get(self, kind):
        ident = self.state["refs"].get(kind)
        if not ident:
            return None
        operation, argument, key, _ = SPEC[kind]
        d = self.aws.call(operation, [argument, ident], absent=True)
        if d is None:
            return None
        if kind == "instance":
            require(all(r["OwnerId"] == self.args.expected_account for r in d[key]), "INSTANCE_OWNER_MISMATCH")
            values = [i for r in d[key] for i in r["Instances"]]
        else:
            values = d[key]
        require(len(values) == 1, "EXACT_RESOURCE_COUNT_REQUIRED")
        item = values[0]
        if not self.state.get("historical_closed"):
            # ENIs inherit ownership from the exact instance attachment; no deletion of leftover ENIs.
            if kind != "eni":
                self.own(item, "web" if kind in ("instance", "volume") else kind)
            if kind in ("subnet", "sg", "rt", "eni"):
                require(item["VpcId"] == self.state["refs"].get("vpc"), "RESOURCE_VPC_MISMATCH")
            if kind == "vpc":
                require(not item["IsDefault"] and item["CidrBlock"] == "10.0.0.0/16", "DEFAULT_OR_WRONG_VPC")
            if kind == "subnet":
                require(item["CidrBlock"] == "10.0.1.0/24", "WRONG_SUBNET_CIDR")
            if kind == "eni":
                require(item.get("OwnerId") == self.args.expected_account and
                        item.get("Attachment", {}).get("InstanceId") == self.state["refs"].get("instance"), "ENI_OWNER_LINK_MISMATCH")
            if kind == "key":
                require(item["KeyName"] == self.state["key_name"] and item["KeyType"] == "ed25519" and
                        item["KeyFingerprint"] == self.state.get("key_fingerprint"), "KEY_IDENTITY_MISMATCH")
            if kind == "rt":
                require(not any(a.get("Main") for a in item["Associations"]), "MAIN_ROUTE_TABLE_FORBIDDEN")
        return item

    def mutate(self, operation, args, payload=None, before_actual=None):
        require(self.state is not None and not self.state.get("historical_closed"), "WRITABLE_STATE_REQUIRED")
        require(self.state["status"] != "UNKNOWN", "UNKNOWN_OPERATION_REQUIRES_MANUAL_RECONCILIATION")
        self.aws.call(operation, [*args, "--dry-run"], dry=True, payload=payload)
        if before_actual:
            before_actual()
        self.state["pending_operation"] = operation
        self.save()  # durable intent BEFORE a potentially ambiguous AWS write
        try:
            result = self.aws.call(operation, args, payload=payload)
        except Exception:
            self.state["status"] = "UNKNOWN"
            self.save()
            raise
        created = {"create-vpc": ("vpc", "Vpc", "VpcId"),
                   "create-subnet": ("subnet", "Subnet", "SubnetId"),
                   "create-internet-gateway": ("igw", "InternetGateway", "InternetGatewayId"),
                   "create-route-table": ("rt", "RouteTable", "RouteTableId"),
                   "create-security-group": ("sg", None, "GroupId"),
                   "associate-route-table": ("assoc", None, "AssociationId")}
        try:
            if operation in created:
                kind, container, field = created[operation]
                ident = (result[container] if container else result)[field]
                require(bool(ident), "MISSING_CREATED_REFERENCE")
                self.state["refs"][kind] = ident
            if operation == "run-instances":
                require(len(result.get("Instances", [])) == 1, "AMBIGUOUS_INSTANCE_RESULT")
                self.state["refs"]["instance"] = result["Instances"][0]["InstanceId"]
            # Durable reference and pending removal happen in ONE atomic state replacement.
            self.state.pop("pending_operation", None)
            self.save()
        except Exception:
            self.state["status"] = "UNKNOWN"
            self.state["pending_operation"] = operation
            self.save()
            raise
        return result

    def remember(self, kind, ident):
        require(bool(ident), "MISSING_CREATED_RESOURCE_REFERENCE")
        self.state["refs"][kind] = ident
        self.save()

    def plan(self, action):
        return {"mode": "PLAN_ONLY", "action": action, "region": REGION,
                "state_exists": self.state is not None,
                "bounds": "one ARM64 t4g.nano, encrypted 8GiB gp3, standard credits, auto IPv4; no cap/free guarantee",
                "apply_required": True, "aws_mutations": 0}

    def create(self):
        require(self.state is None, "STATE_EXISTS_NO_SILENT_RECREATE_OR_RESUME")
        run = self.args.run_id
        require(re.fullmatch(r"[a-z0-9][a-z0-9-]{2,30}", run or ""), "UNIQUE_RUN_ID_REQUIRED")
        self.identity()
        key_path = secure_path(ROOT / ".secrets" / ("key-" + run + ".pem"), ROOT / ".secrets")
        require(not key_path.exists(), "PRIVATE_FILE_EXISTS_NO_OVERWRITE")
        require(subprocess.run(["git", "-C", str(ROOT), "check-ignore", "--", str(key_path)],
                               capture_output=True).returncode == 0, "PRIVATE_FILE_MUST_BE_IGNORED")
        key_name = "b6-1-" + run + "-key"
        found = self.aws.call("describe-key-pairs", ["--filters", "Name=key-name,Values=" + key_name])
        require(not found["KeyPairs"], "CLOUD_KEY_EXISTS_NO_REGEN_OR_IMPORT")
        collision = self.aws.call("describe-vpcs", ["--filters", "Name=tag:Project,Values=B6-1",
                                                     "Name=tag:RunId,Values=" + run])
        require(not collision["Vpcs"], "RUN_RESOURCE_COLLISION")
        salt = secrets.token_hex(24)
        self.state = {"schema": 1, "status": "CREATING", "run_id": run, "region": REGION,
                      "profile": self.args.profile, "account_salt": salt,
                      "account_binding": account_binding(salt, self.args.expected_account),
                      "iam_user": self.args.iam_user, "refs": {}, "key_name": key_name,
                      "key_path": str(key_path), "events": []}
        self.save()
        type_info = self.aws.call("describe-instance-types", ["--instance-types", "t4g.nano"])["InstanceTypes"][0]
        require(type_info["MemoryInfo"]["SizeInMiB"] == 512 and
                "arm64" in type_info["ProcessorInfo"]["SupportedArchitectures"], "NANO_ARM64_REQUIRED")
        image_args = ["--owners", "amazon", "--filters", "Name=architecture,Values=arm64",
                      "Name=state,Values=available", "Name=virtualization-type,Values=hvm",
                      "Name=root-device-type,Values=ebs"]
        if self.args.ami:
            image_args += ["--image-ids", self.args.ami]
        else:
            image_args += ["Name=name,Values=al2023-ami-minimal-2023.*-arm64"]
        images = self.aws.call("describe-images", image_args)["Images"]
        require(bool(images), "NO_TRUSTED_COMPATIBLE_AMI")
        image = max(images, key=lambda i: i["CreationDate"])
        root = next(b for b in image["BlockDeviceMappings"] if b["DeviceName"] == image["RootDeviceName"])
        require(image.get("ImageOwnerAlias") == "amazon" and root["Ebs"]["VolumeSize"] <= 8,
                "AMI_OWNER_OR_ROOT_SIZE_UNSUITABLE_NO_FALLBACK")
        source = self.ip_lookup()
        zones = self.aws.call("describe-availability-zones", ["--filters", "Name=state,Values=available",
                                                              "Name=zone-type,Values=availability-zone"])["AvailabilityZones"]
        available = sorted(z["ZoneName"] for z in zones)
        require(bool(available), "NO_AVAILABLE_STANDARD_AZ")
        az = "ap-northeast-2a" if "ap-northeast-2a" in available else available[0]
        v = self.mutate("create-vpc", ["--cidr-block", "10.0.0.0/16", *self.tag_spec("vpc", "vpc")])
        self.remember("vpc", v["Vpc"]["VpcId"])
        sub = self.mutate("create-subnet", ["--vpc-id", self.state["refs"]["vpc"], "--cidr-block", "10.0.1.0/24",
                                           "--availability-zone", az, *self.tag_spec("subnet", "subnet")])
        self.remember("subnet", sub["Subnet"]["SubnetId"])
        ig = self.mutate("create-internet-gateway", self.tag_spec("internet-gateway", "igw"))
        self.remember("igw", ig["InternetGateway"]["InternetGatewayId"])
        self.mutate("attach-internet-gateway", ["--internet-gateway-id", self.state["refs"]["igw"],
                                                "--vpc-id", self.state["refs"]["vpc"]])
        rt = self.mutate("create-route-table", ["--vpc-id", self.state["refs"]["vpc"], *self.tag_spec("route-table", "rt")])
        self.remember("rt", rt["RouteTable"]["RouteTableId"])
        self.mutate("create-route", ["--route-table-id", self.state["refs"]["rt"], "--destination-cidr-block", "0.0.0.0/0",
                                     "--gateway-id", self.state["refs"]["igw"]])
        assoc = self.mutate("associate-route-table", ["--route-table-id", self.state["refs"]["rt"],
                                                     "--subnet-id", self.state["refs"]["subnet"]])
        self.remember("assoc", assoc["AssociationId"])
        sg = self.mutate("create-security-group", ["--group-name", "b6-1-" + run + "-sg", "--description", "B6-1 web lab",
                                                  "--vpc-id", self.state["refs"]["vpc"], *self.tag_spec("security-group", "sg")])
        self.remember("sg", sg["GroupId"])
        require(self.ip_lookup() == source, "SOURCE_IP_CHANGED_NO_INGRESS_WRITE")
        permissions = [{"IpProtocol": "tcp", "FromPort": port, "ToPort": port,
                        "IpRanges": [{"CidrIp": cidr}]} for port, cidr in [(80, "0.0.0.0/0"), (22, source + "/32")]]
        self.mutate("authorize-security-group-ingress", [], payload={"GroupId": self.state["refs"]["sg"],
                                                                    "IpPermissions": permissions},
                    before_actual=lambda: require(self.ip_lookup() == source, "SOURCE_IP_CHANGED_NO_INGRESS_WRITE"))
        self.create_key(key_path)
        raw = self.path.parent / (run + "-user-data.sh")
        require(not raw.exists(), "RENDER_OUTPUT_EXISTS")
        require(subprocess.run([sys.executable, str(ROOT / "deploy/render-user-data.py"), "--output", str(raw)],
                               capture_output=True).returncode == 0, "RENDER_FAILED")
        os.chmod(raw, 0o600)
        fields = {"ImageId": image["ImageId"], "InstanceType": "t4g.nano", "MinCount": 1, "MaxCount": 1,
                  "KeyName": key_name, "CreditSpecification": {"CpuCredits": "standard"},
                  "MetadataOptions": {"HttpTokens": "required", "HttpPutResponseHopLimit": 1},
                  "BlockDeviceMappings": [{"DeviceName": image["RootDeviceName"], "Ebs": {
                      "VolumeSize": 8, "VolumeType": "gp3", "Encrypted": True, "DeleteOnTermination": True}}],
                  "NetworkInterfaces": [{"DeviceIndex": 0, "SubnetId": self.state["refs"]["subnet"],
                                         "Groups": [self.state["refs"]["sg"]], "AssociatePublicIpAddress": True,
                                         "DeleteOnTermination": True}],
                  "TagSpecifications": [{"ResourceType": t, "Tags": self.tags("web")} for t in ("instance", "volume")]}
        seed = json.dumps({"fields": fields, "user_data_hash": hashlib.sha256(raw.read_bytes()).hexdigest()},
                          sort_keys=True, separators=(",", ":"))
        fields["ClientToken"] = "b6-1-" + hashlib.sha256(seed.encode()).hexdigest()[:48]
        self.state["client_token"] = fields["ClientToken"]
        payload = self.path.parent / (run + "-launch.json")
        require(not payload.exists(), "LAUNCH_INPUT_EXISTS")
        atomic_state(payload, fields, create_only=True)
        collision = self.aws.call("describe-instances", ["--filters", "Name=tag:RunId,Values=" + run,
                                                         "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down"])
        require(not any(r["Instances"] for r in collision["Reservations"]), "INSTANCE_COLLISION_NO_DUPLICATE")
        result = self.mutate("run-instances", ["--cli-input-json", "file://" + str(payload),
                                               "--user-data", "file://" + str(raw)])
        require(len(result.get("Instances", [])) == 1, "AMBIGUOUS_INSTANCE_COUNT_NO_RETRY")
        self.remember("instance", result["Instances"][0]["InstanceId"])
        self.state["status"] = "ACTIVE"
        self.save()
        return {"status": "ACTIVE_BOOTSTRAP_PENDING", "refs": self.state["refs"],
                "next": "status / verify after bootstrap; no automatic resize or relaunch"}

    def create_key(self, path):
        require(not path.exists(), "PRIVATE_FILE_EXISTS_NO_OVERWRITE")
        secure_path(path, ROOT / ".secrets")
        path.parent.mkdir(mode=0o700, exist_ok=True)
        require(path.parent.stat().st_uid == os.getuid() and stat.S_IMODE(path.parent.stat().st_mode) == 0o700,
                "INSECURE_SECRET_DIRECTORY")
        args = ["--key-name", self.state["key_name"], "--key-type", "ed25519", "--key-format", "pem",
                *self.tag_spec("key-pair", "key")]
        self.aws.call("create-key-pair", [*args, "--dry-run"], dry=True)
        secure_path(path, ROOT / ".secrets")
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            self.state["pending_operation"] = "create-key-pair"
            self.state["status"] = "UNKNOWN"
            self.save()
            result = self.aws.raw("ec2", "create-key-pair", args)
            if result.returncode:
                print("KEY_CREATE_UNKNOWN_NO_RETRY_RESPONSE_RETAINED_IN_MEMORY", flush=True)
                while True:
                    self.sleep(5)
            safe = persist_key_response(result.stdout, fd)
            result.stdout = ""
            result.stderr = ""
        finally:
            os.close(fd)
        described = self.aws.call("describe-key-pairs", ["--key-names", self.state["key_name"], "--include-public-key"])["KeyPairs"]
        require(len(described) == 1, "KEY_RESULT_REQUIRES_RECONCILIATION")
        key = described[0]
        self.own(key, "key")
        require(key["KeyType"] == "ed25519" and (not safe["id"] or safe["id"] == key["KeyPairId"]), "KEY_RESULT_MISMATCH")
        derived = subprocess.run(["ssh-keygen", "-y", "-f", str(path)], capture_output=True, text=True)
        require(derived.returncode == 0 and derived.stdout.split()[:2] == key["PublicKey"].split()[:2], "KEY_CORRESPONDENCE_FAILED")
        self.state["refs"]["key"] = key["KeyPairId"]
        self.state["key_fingerprint"] = key["KeyFingerprint"]
        self.state["status"] = "CREATING"
        self.state.pop("pending_operation", None)
        self.save()

    def capture_instance_refs(self):
        instance = self.get("instance")
        if not instance or instance["State"]["Name"] == "terminated":
            return
        require(instance.get("VpcId") == self.state["refs"].get("vpc") and
                instance.get("KeyName") == self.state["key_name"], "INSTANCE_LINK_MISMATCH")
        require(len(instance["BlockDeviceMappings"]) == 1 and len(instance["NetworkInterfaces"]) == 1,
                "UNEXPECTED_INSTANCE_DISK_OR_ENI")
        disk = instance["BlockDeviceMappings"][0]["Ebs"]
        eni = instance["NetworkInterfaces"][0]
        require(disk["DeleteOnTermination"] and eni["Attachment"]["DeleteOnTermination"], "AUTO_DELETE_FLAGS_CHANGED")
        for kind, ident in [("volume", disk["VolumeId"]), ("eni", eni["NetworkInterfaceId"])]:
            require(not self.state["refs"].get(kind) or self.state["refs"][kind] == ident, "INSTANCE_RESOURCE_CHANGED")
            self.state["refs"][kind] = ident
        volume = self.get("volume")
        require(volume and volume["Size"] == 8 and volume["VolumeType"] == "gp3" and volume["Encrypted"], "ROOT_VOLUME_UNSUITABLE")
        self.get("eni")
        self.save()

    def target_preflight(self):
        # All owner/tag/link/Main guards run BEFORE any termination, not just before the last VPC delete.
        for kind in ("vpc", "subnet", "igw", "rt", "sg", "key"):
            self.get(kind)
        self.capture_instance_refs()

    def foreign_guard(self):
        vpc = self.state["refs"].get("vpc")
        if not vpc or self.get("vpc") is None:
            return
        for kind, operation, collection, id_key in [
                ("subnet", "describe-subnets", "Subnets", "SubnetId"),
                ("sg", "describe-security-groups", "SecurityGroups", "GroupId"),
                ("rt", "describe-route-tables", "RouteTables", "RouteTableId"),
                ("eni", "describe-network-interfaces", "NetworkInterfaces", "NetworkInterfaceId")]:
            data = self.aws.call(operation, ["--filters", "Name=vpc-id,Values=" + vpc])[collection]
            for item in data:
                default = kind == "sg" and item["GroupName"] == "default" or kind == "rt" and any(
                    a.get("Main") for a in item["Associations"])
                require(default or item[id_key] == self.state["refs"].get(kind), "FOREIGN_VPC_DEPENDENCY")
                if not default:
                    self.get(kind)  # validates current owner/run tag/link and non-main RT

        instances = self.aws.call("describe-instances", ["--filters", "Name=vpc-id,Values=" + vpc,
                                                        "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down"])
        require(all(i["InstanceId"] == self.state["refs"].get("instance")
                    for r in instances["Reservations"] for i in r["Instances"]), "FOREIGN_INSTANCE")
        gateways = self.aws.call("describe-internet-gateways", ["--filters", "Name=attachment.vpc-id,Values=" + vpc])
        require(all(g["InternetGatewayId"] == self.state["refs"].get("igw") for g in gateways["InternetGateways"]),
                "FOREIGN_IGW")

    def destroyed_noop(self):
        for kind in SPEC:
            item = self.get(kind)
            if kind == "instance" and item and item["State"]["Name"] == "terminated":
                require(not item.get("PublicIpAddress"), "PUBLIC_ASSOCIATION_REMAINS")
                continue
            require(item is None, "DESTROYED_STATE_RESOURCE_REAPPEARED_NO_WRITES")
        return {"status": "DESTROYED_NOOP_TARGET_READS_VERIFIED", "aws_mutations": 0,
                "old_endpoint_probed": False, "local_key_retained": True}

    def destroy(self):
        require(self.state is not None, "STATE_REQUIRED_FOR_DESTROY")
        self.identity()
        if self.state["status"] == "DESTROYED":
            return self.destroyed_noop()
        require(not self.state.get("historical_closed"), "HISTORICAL_STATE_READ_ONLY")
        require(self.state["status"] in ("ACTIVE", "CREATING", "DESTROYING")
                and not self.state.get("pending_operation"), "UNKNOWN_OPERATION_REQUIRES_MANUAL_RECONCILIATION")
        self.target_preflight()
        self.foreign_guard()
        self.state["status"] = "DESTROYING"
        self.save()
        instance = self.get("instance")
        if instance and instance["State"]["Name"] != "terminated":
            require(instance["VpcId"] == self.state["refs"].get("vpc") and instance["KeyName"] == self.state["key_name"],
                    "INSTANCE_LINK_MISMATCH")
            require(len(instance["BlockDeviceMappings"]) == 1 and len(instance["NetworkInterfaces"]) == 1,
                    "UNEXPECTED_INSTANCE_DISK_OR_ENI")
            volume = instance["BlockDeviceMappings"][0]["Ebs"]
            eni = instance["NetworkInterfaces"][0]
            require(volume["DeleteOnTermination"] and eni["Attachment"]["DeleteOnTermination"], "AUTO_DELETE_FLAGS_CHANGED")
            if self.state["refs"].get("volume"):
                require(self.state["refs"]["volume"] == volume["VolumeId"], "ROOT_VOLUME_CHANGED")
            if self.state["refs"].get("eni"):
                require(self.state["refs"]["eni"] == eni["NetworkInterfaceId"], "ENI_CHANGED")
            self.remember("volume", volume["VolumeId"])
            self.remember("eni", eni["NetworkInterfaceId"])
            disk = self.get("volume")
            require(disk and disk["Size"] == 8 and disk["VolumeType"] == "gp3" and disk["Encrypted"], "ROOT_VOLUME_UNSUITABLE")
            self.mutate("terminate-instances", ["--instance-ids", self.state["refs"]["instance"]])
        for _ in range(24):
            instance = self.get("instance")
            if instance is None or instance["State"]["Name"] == "terminated":
                break
            self.sleep(5)
        else:
            raise LabError("TERMINATION_PENDING_NO_FURTHER_DELETION")
        require(instance is None or not instance.get("PublicIpAddress"), "PUBLIC_ASSOCIATION_PENDING")
        for kind in ("volume", "eni"):
            delete_requested = False
            for _ in range(18):
                item = self.get(kind)
                if item is None:
                    break
                if kind == "volume" and not delete_requested and item["State"] == "available" and not item["Attachments"]:
                    self.mutate("delete-volume", ["--volume-id", self.state["refs"][kind]])
                    delete_requested = True
                self.sleep(5)
            else:
                raise LabError("LEFTOVER_" + kind.upper() + "_NO_BLIND_DELETE")
        rt = self.get("rt")
        if rt:
            associations = [a for a in rt["Associations"] if not a.get("Main")]
            require(all(a.get("SubnetId") == self.state["refs"].get("subnet") and
                        a["RouteTableAssociationId"] == self.state["refs"].get("assoc") for a in associations),
                    "FOREIGN_ROUTE_ASSOCIATION")
            if associations:
                self.mutate("disassociate-route-table", ["--association-id", self.state["refs"]["assoc"]])
            rt = self.get("rt")
            routes = [v for v in rt["Routes"] if v.get("GatewayId") != "local"]
            require(all(v.get("DestinationCidrBlock") == "0.0.0.0/0" and v.get("GatewayId") == self.state["refs"].get("igw")
                        for v in routes), "FOREIGN_ROUTE")
            if routes:
                self.mutate("delete-route", ["--route-table-id", self.state["refs"]["rt"], "--destination-cidr-block", "0.0.0.0/0"])
            rt = self.get("rt")
            require(not rt["Associations"] and all(v.get("GatewayId") == "local" for v in rt["Routes"]), "ROUTE_TABLE_STILL_USED")
            self.mutate("delete-route-table", ["--route-table-id", self.state["refs"]["rt"]])
        for kind, operation, flag in [("subnet", "delete-subnet", "--subnet-id"), ("sg", "delete-security-group", "--group-id")]:
            if self.get(kind):
                self.foreign_guard()
                self.mutate(operation, [flag, self.state["refs"][kind]])
        igw = self.get("igw")
        if igw:
            require(all(a["VpcId"] == self.state["refs"].get("vpc") for a in igw["Attachments"]), "IGW_FOREIGN_ATTACHMENT")
            if igw["Attachments"]:
                self.mutate("detach-internet-gateway", ["--internet-gateway-id", self.state["refs"]["igw"],
                                                        "--vpc-id", self.state["refs"]["vpc"]])
            igw = self.get("igw")
            require(not igw["Attachments"], "IGW_STILL_ATTACHED")
            self.mutate("delete-internet-gateway", ["--internet-gateway-id", self.state["refs"]["igw"]])
        if self.get("key"):
            refs = self.aws.call("describe-instances", ["--filters", "Name=key-name,Values=" + self.state["key_name"],
                                                        "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down"])
            require(not any(r["Instances"] for r in refs["Reservations"]), "KEY_STILL_REFERENCED")
            self.mutate("delete-key-pair", ["--key-pair-id", self.state["refs"]["key"]])
        if self.get("vpc"):
            self.foreign_guard()
            for kind in ("subnet", "sg", "rt", "eni", "igw"):
                require(self.get(kind) is None, "VPC_DEPENDENCY_REMAINS")
            self.mutate("delete-vpc", ["--vpc-id", self.state["refs"]["vpc"]])
        verified = self.destroyed_noop()
        self.state["status"] = "DESTROYED"
        self.state.pop("public_endpoint", None)
        self.save()
        return verified

    def status(self):
        require(self.state is not None, "STATE_REQUIRED")
        self.identity()
        if self.state["status"] == "DESTROYED":
            return self.destroyed_noop()
        result = {"status": self.state["status"], "refs": self.state["refs"], "endpoint_probed": False,
                  "pending_operation": self.state.get("pending_operation"),
                  "manual_reconciliation_required": self.state["status"] == "UNKNOWN"}
        instance = self.get("instance")
        if instance:
            result["instance_state"] = instance["State"]["Name"]
            if instance["State"]["Name"] == "running" and instance.get("PublicIpAddress"):
                result["public_endpoint"] = "http://" + instance["PublicIpAddress"] + "/"
        return result

    def verify(self):
        require(self.state is not None and self.state["status"] == "ACTIVE", "ACTIVE_STATE_REQUIRED_NO_OLD_ENDPOINT_PROBE")
        result = self.status()
        require(result.get("instance_state") == "running" and result.get("public_endpoint"), "INSTANCE_NOT_READY")
        host = result["public_endpoint"].split("/")[2]
        key = secure_path(self.state["key_path"], ROOT / ".secrets")
        require(key.exists() and stat.S_IMODE(key.stat().st_mode) == 0o600, "SECURE_PRIVATE_KEY_REQUIRED")
        # stdout is captured privately and never relayed (could contain network/client identifiers).
        command = "cd /opt/b6-1 && sudo -n docker compose config --quiet && sudo -n docker ps --filter status=running --format '{{.Status}}' && curl --fail --silent http://127.0.0.1/health && curl --fail --silent --show-error -o /dev/null https://example.com"
        q = subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new",
                            "-o", "UserKnownHostsFile=" + str(self.path.parent / (self.state["run_id"] + "-known_hosts")),
                            "-i", str(key), "ec2-user@" + host, command], capture_output=True, text=True, timeout=55)
        require(q.returncode == 0 and "healthy" in q.stdout and "B6-1 OK" in q.stdout, "SSH_RUNTIME_NOT_VERIFIED")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        for suffix in ("", "health"):
            with opener.open(result["public_endpoint"] + suffix, timeout=15) as response:
                body = response.read(65536)
                require(response.status == 200, "HTTP_NOT_200")
                require(body == ((ROOT / "app/index.html").read_bytes() if not suffix else b"B6-1 OK\n"), "HTTP_SOURCE_MISMATCH")
        return {"status": "VERIFIED", "public_endpoint": result["public_endpoint"], "ssh_health_outbound": True,
                "external_http_source_match": True}


def parser():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=("create", "destroy", "status", "verify"))
    p.add_argument("--apply", action="store_true", help="explicit paid create or destructive destroy authorization")
    p.add_argument("--profile", default="b6-1-iam")
    p.add_argument("--region", default=REGION)
    p.add_argument("--state", type=Path, default=ROOT / "runtime/lab-state.json")
    p.add_argument("--expected-account", default=os.environ.get("B6_EXPECTED_ACCOUNT"))
    p.add_argument("--iam-user", default=os.environ.get("B6_IAM_USER"))
    p.add_argument("--run-id", help="new unique lowercase run ID, 3..31 characters")
    p.add_argument("--ami", help="optional trusted Amazon AL2023 ARM64 image ID; no size/type fallback")
    return p


def main():
    require(not sys.flags.optimize, "OPTIMIZED_INTERPRETER_FORBIDDEN")
    args = parser().parse_args()
    if args.action in ("create", "destroy") and not args.apply:
        require(args.region == REGION, "SEOUL_REGION_REQUIRED")
        secure_path(args.state, ROOT / "runtime")
        result = {"mode": "PLAN_ONLY", "action": args.action, "region": REGION,
                  "state": str(args.state), "aws_calls": 0, "aws_mutations": 0,
                  "apply_required": True, "binding_required_before_apply": True,
                  "bounds": "one t4g.nano ARM64 / encrypted8GiB / standard credits / autoIPv4; no cost cap"}
    else:
        lab = Lab(args)
        result = getattr(lab, args.action)()
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except LabError as error:
        print(json.dumps({"status": "BLOCKED", "reason": str(error)}))
        sys.exit(1)
    except (OSError, ValueError, KeyError, TypeError, StopIteration, subprocess.SubprocessError):
        # Never echo untrusted CLI stderr, identity, source IP, key response or exception locals.
        print(json.dumps({"status": "BLOCKED", "reason": "CHECK_INPUT_STATE_OR_AUTH; no blind retry; see scripts/README.md"}))
        sys.exit(1)
