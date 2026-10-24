"""Offline fixtures only: no AWS/network; dummy key bytes never printed."""
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('lab', Path(__file__).parents[1] / 'scripts/lab.py')
lab = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lab)
ACCOUNT = '1' * 12
USER = 'fixture-user'
SOURCE = str(lab.ipaddress.IPv4Address(0x08080808))
PUBLIC = 'fixture-type fixture-public-data'


class FakeAWS:
    def __init__(self):
        self.events = []
        self.db = {}
        self.counter = 0
        self.mutations = []
        self.ambiguous = None
        self.saved_payloads = []

    def ident(self, kind):
        self.counter += 1
        return lab.SPEC[kind][3] + '-' + format(self.counter, '017x')

    def raw(self, service, op, args, payload=None):
        if op != 'create-key-pair':
            raise AssertionError('unexpected raw operation')
        result = self.call(op, args)
        result['KeyMaterial'] = 'fixture-only-not-a-real-key'
        # Deliberately omit optional KeyType from CreateKeyPair response.
        return subprocess.CompletedProcess([], 0, json.dumps(result), '')

    def call(self, op, args=(), *, service='ec2', absent=False, dry=False, payload=None):
        args = list(args)
        self.events.append({'operation': op, 'dry': dry})
        def value(flag):
            return args[args.index(flag) + 1]
        def tags():
            return json.loads(value('--tag-specifications'))[0]['Tags']
        if op == 'get-caller-identity':
            return {'Account': ACCOUNT, 'Arn': 'arn:aws:iam::' + ACCOUNT + ':user/' + USER}
        if dry:
            return None
        if op == 'describe-instance-types':
            return {'InstanceTypes': [{'MemoryInfo': {'SizeInMiB': 512}, 'ProcessorInfo': {'SupportedArchitectures': ['arm64']}}]}
        if op == 'describe-images':
            return {'Images': [{'ImageId': 'ami-' + 'a' * 17, 'CreationDate': 'fixture', 'ImageOwnerAlias': 'amazon',
                                'RootDeviceName': '/dev/xvda', 'BlockDeviceMappings': [{'DeviceName': '/dev/xvda', 'Ebs': {'VolumeSize': 2}}]}]}
        if op == 'describe-availability-zones':
            return {'AvailabilityZones': [{'ZoneName': 'ap-northeast-2a'}]}
        for kind, (operation, flag, root, prefix) in lab.SPEC.items():
            if op != operation:
                continue
            if flag in args:
                item = self.db.get(kind)
                if not item or item.get('id') != value(flag):
                    if absent:
                        return None
                    raise lab.LabError('FIXTURE_TYPED_NOT_FOUND')
                values = [copy.deepcopy(item)]
            elif op == 'describe-key-pairs' and '--key-names' in args:
                values = [copy.deepcopy(self.db['key'])] if 'key' in self.db and self.db['key']['KeyName'] == value('--key-names') else []
            else:
                values = [copy.deepcopy(self.db[kind])] if kind in self.db else []
                filters = ' '.join(args)
                if kind == 'key' and 'Name=key-name,Values=' in filters:
                    name = filters.split('Name=key-name,Values=')[1].split()[0]
                    values = [x for x in values if x['KeyName'] == name]
                if 'Name=tag:RunId' in filters:
                    run = filters.split('Name=tag:RunId,Values=')[1].split()[0]
                    values = [x for x in values if {'Key': 'RunId', 'Value': run} in x.get('Tags', [])]
                if kind == 'instance' and 'Name=instance-state-name' in filters:
                    values = [x for x in values if x['State']['Name'] != 'terminated']
                if 'Name=vpc-id' in filters:
                    vpc = filters.split('Name=vpc-id,Values=')[1].split()[0]
                    values = [x for x in values if x.get('VpcId') == vpc]
                if kind == 'igw' and 'attachment.vpc-id' in filters:
                    values = [x for x in values if x['Attachments']]
            if kind == 'instance':
                return {'Reservations': [{'OwnerId': ACCOUNT, 'Instances': values}] if values else []}
            return {root: values}
        self.mutations.append(op)
        if op == self.ambiguous:
            raise lab.LabError('AMBIGUOUS_FIXTURE_RESPONSE')
        mapping = {'create-vpc': ('vpc', 'Vpc', 'VpcId'), 'create-subnet': ('subnet', 'Subnet', 'SubnetId'),
                   'create-internet-gateway': ('igw', 'InternetGateway', 'InternetGatewayId'),
                   'create-route-table': ('rt', 'RouteTable', 'RouteTableId'),
                   'create-security-group': ('sg', None, 'GroupId'), 'create-key-pair': ('key', None, 'KeyPairId')}
        if op in mapping:
            kind, root, field = mapping[op]
            ident = self.ident(kind)
            item = {'id': ident, field: ident, 'OwnerId': ACCOUNT, 'Tags': tags()}
            if kind == 'vpc':
                item.update(CidrBlock='10.0.0.0/16', IsDefault=False)
            if kind in ('subnet', 'rt', 'sg'):
                item['VpcId'] = value('--vpc-id')
            if kind == 'subnet':
                item.update(CidrBlock='10.0.1.0/24', State='available')
            if kind == 'igw':
                item['Attachments'] = []
            if kind == 'rt':
                item.update(Associations=[], Routes=[{'GatewayId': 'local'}])
            if kind == 'sg':
                item.update(GroupName=value('--group-name'), IpPermissions=[])
            if kind == 'key':
                item.update(KeyName=value('--key-name'), KeyType='ed25519', KeyFingerprint='fixture-fingerprint', PublicKey=PUBLIC)
            self.db[kind] = item
            result = {field: ident, **({'KeyFingerprint': 'fixture-fingerprint'} if kind == 'key' else {})}
            return {root: copy.deepcopy(item)} if root else result
        if op == 'attach-internet-gateway':
            self.db['igw']['Attachments'] = [{'VpcId': value('--vpc-id')}]
        elif op == 'create-route':
            self.db['rt']['Routes'].append({'DestinationCidrBlock': '0.0.0.0/0', 'GatewayId': value('--gateway-id')})
        elif op == 'associate-route-table':
            ident = 'rtbassoc-' + 'a' * 17
            self.db['rt']['Associations'] = [{'Main': False, 'SubnetId': value('--subnet-id'), 'RouteTableAssociationId': ident}]
            return {'AssociationId': ident}
        elif op == 'authorize-security-group-ingress':
            self.saved_payloads.append(copy.deepcopy(payload))
            self.db['sg']['IpPermissions'] = payload['IpPermissions']
        elif op == 'run-instances':
            fields = json.loads(Path(value('--cli-input-json')[7:]).read_text())
            ident = self.ident('instance')
            volume, eni = self.ident('volume'), self.ident('eni')
            webtags = next(t['Tags'] for t in fields['TagSpecifications'] if t['ResourceType'] == 'volume')
            self.db['volume'] = {'id': volume, 'VolumeId': volume, 'Size': 8, 'VolumeType': 'gp3', 'Encrypted': True, 'Tags': webtags}
            self.db['eni'] = {'id': eni, 'NetworkInterfaceId': eni, 'OwnerId': ACCOUNT, 'VpcId': self.db['vpc']['id'],
                              'Attachment': {'InstanceId': ident, 'DeleteOnTermination': True}, 'Groups': [{'GroupId': self.db['sg']['id']}],
                              'SubnetId': self.db['subnet']['id']}
            item = {'id': ident, 'InstanceId': ident, 'InstanceType': 't4g.nano', 'VpcId': self.db['vpc']['id'],
                    'KeyName': fields['KeyName'], 'Tags': webtags, 'State': {'Name': 'running'},
                    'BlockDeviceMappings': [{'Ebs': {'VolumeId': volume, 'DeleteOnTermination': True}}],
                    'NetworkInterfaces': [copy.deepcopy(self.db['eni'])]}
            self.db['instance'] = item
            return {'Instances': [copy.deepcopy(item)]}
        elif op == 'terminate-instances':
            self.db['instance']['State'] = {'Name': 'terminated'}
            self.db['instance'].pop('VpcId', None)
            self.db['instance']['BlockDeviceMappings'] = []
            self.db['instance']['NetworkInterfaces'] = []
            self.db.pop('volume', None)
            self.db.pop('eni', None)
        elif op == 'disassociate-route-table':
            self.db['rt']['Associations'] = []
        elif op == 'delete-route':
            self.db['rt']['Routes'] = [{'GatewayId': 'local'}]
        elif op == 'detach-internet-gateway':
            self.db['igw']['Attachments'] = []
        elif op.startswith('delete-'):
            kind = {'delete-route-table': 'rt', 'delete-subnet': 'subnet', 'delete-security-group': 'sg',
                    'delete-internet-gateway': 'igw', 'delete-key-pair': 'key', 'delete-vpc': 'vpc'}[op]
            self.db.pop(kind, None)
        else:
            raise AssertionError('unimplemented fixture op ' + op)
        return {}


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.old_root = lab.ROOT
        lab.ROOT = self.root
        (self.root / 'runtime').mkdir()
        (self.root / '.secrets').mkdir(mode=0o700)
        self.aws = FakeAWS()
        self.args = lab.parser().parse_args(['create', '--state', str(self.root / 'runtime/state.json'),
                                            '--run-id', 'fixture-run', '--expected-account', ACCOUNT, '--iam-user', USER])
        self.obj = lab.Lab(self.args, self.aws, lambda: SOURCE, lambda _: None)
        self.real_run = subprocess.run
        def runner(argv, **kwargs):
            if argv[0] == 'git':
                return subprocess.CompletedProcess(argv, 0, '', '')
            if argv[0] == 'ssh-keygen':
                return subprocess.CompletedProcess(argv, 0, PUBLIC, '')
            if argv[0] == sys.executable and 'render-user-data.py' in argv[1]:
                Path(argv[-1]).write_text('#!/bin/sh\n# fixture-only\n')
                return subprocess.CompletedProcess(argv, 0, '', '')
            raise AssertionError('Unexpected real process')
        self.patch = patch.object(lab.subprocess, 'run', side_effect=runner)
        self.patch.start()

    def tearDown(self):
        self.patch.stop()
        lab.ROOT = self.old_root
        self.temp.cleanup()

    def create(self):
        self.obj.create()
        return self.obj

    def test_full_create_destroy_dependency_order_and_noop(self):
        obj = self.create()
        self.assertNotIn('eni', obj.state['refs'])  # exercises durable capture BEFORE foreign guard
        result = obj.destroy()
        self.assertEqual(result['status'], 'DESTROYED_NOOP_TARGET_READS_VERIFIED')
        deletes = self.aws.mutations[self.aws.mutations.index('terminate-instances'):]
        self.assertEqual(deletes, ['terminate-instances', 'disassociate-route-table', 'delete-route', 'delete-route-table',
                                  'delete-subnet', 'delete-security-group', 'detach-internet-gateway',
                                  'delete-internet-gateway', 'delete-key-pair', 'delete-vpc'])
        count = len(self.aws.mutations)
        self.assertEqual(obj.destroy()['aws_mutations'], 0)
        self.assertEqual(len(self.aws.mutations), count)
        self.assertTrue((self.root / '.secrets/key-fixture-run.pem').exists())
        self.assertNotIn(SOURCE, obj.path.read_text())
        self.assertNotIn(ACCOUNT, obj.path.read_text())
        self.assertNotIn('KeyMaterial', obj.path.read_text())

    def test_upfront_main_tag_and_foreign_reject_before_termination(self):
        obj = self.create()
        count = len(self.aws.mutations)
        self.aws.db['rt']['Associations'][0]['Main'] = True
        with self.assertRaisesRegex(lab.LabError, 'MAIN_ROUTE_TABLE'):
            obj.destroy()
        self.assertEqual(len(self.aws.mutations), count)
        self.aws.db['rt']['Associations'][0]['Main'] = False
        self.aws.db['sg']['Tags'] = []
        with self.assertRaisesRegex(lab.LabError, 'RUN_TAG'):
            obj.destroy()
        self.assertEqual(len(self.aws.mutations), count)
        self.aws.db['sg']['Tags'] = obj.tags('sg')
        old = self.aws.call
        def foreign(op, args=(), **kwargs):
            result = old(op, args, **kwargs)
            if op == 'describe-subnets' and '--filters' in args:
                result['Subnets'].append({'SubnetId': 'subnet-' + 'f' * 17})
            return result
        self.aws.call = foreign
        with self.assertRaisesRegex(lab.LabError, 'FOREIGN'):
            obj.destroy()
        self.assertEqual(len(self.aws.mutations), count)

    def test_wrong_principal_account_region_and_missing_state(self):
        self.args.region = 'us-east-1'
        with self.assertRaisesRegex(lab.LabError, 'SEOUL'):
            lab.Lab(self.args, self.aws)
        self.args.region = lab.REGION
        self.args.expected_account = '2' * 12
        with self.assertRaisesRegex(lab.LabError, 'WRONG_ACCOUNT'):
            lab.Lab(self.args, self.aws).identity()
        self.args.expected_account = ACCOUNT
        self.args.iam_user = 'root'
        with self.assertRaisesRegex(lab.LabError, 'NON_IAM'):
            lab.Lab(self.args, self.aws).identity()
        with self.assertRaisesRegex(lab.LabError, 'STATE_REQUIRED'):
            self.obj.destroy()
        self.assertEqual(self.aws.mutations, [])

    def test_existing_key_no_overwrite_and_ambiguous_instance_no_duplicate(self):
        secret = self.root / '.secrets/key-fixture-run.pem'
        secret.write_text('fixture sentinel')
        with self.assertRaisesRegex(lab.LabError, 'NO_OVERWRITE'):
            self.obj.create()
        self.assertEqual(secret.read_text(), 'fixture sentinel')
        self.assertEqual(self.aws.mutations, [])
        secret.unlink()
        self.aws.ambiguous = 'run-instances'
        with self.assertRaisesRegex(lab.LabError, 'AMBIGUOUS'):
            self.obj.create()
        self.assertEqual(self.obj.state['status'], 'UNKNOWN')
        self.assertEqual(self.obj.state['pending_operation'], 'run-instances')
        with self.assertRaisesRegex(lab.LabError, 'STATE_EXISTS'):
            self.obj.create()
        self.assertEqual(self.aws.mutations.count('run-instances'), 1)
        self.assertEqual(self.aws.mutations.count('create-key-pair'), 1)

    def test_reference_saved_before_pending_cleared(self):
        obj = self.create()
        self.assertIn('instance', json.loads(obj.path.read_text())['refs'])
        self.assertNotIn('pending_operation', json.loads(obj.path.read_text()))
        self.assertEqual(os.stat(obj.path).st_mode & 0o777, 0o600)

    def test_wrong_account_binding_and_actual_root_rejected(self):
        obj = self.create()
        self.args.expected_account = '2' * 12
        count = len(self.aws.mutations)
        with self.assertRaisesRegex(lab.LabError, 'STATE_ACCOUNT_MISMATCH'):
            lab.Lab(self.args, self.aws)
        self.args.expected_account = ACCOUNT
        old = self.aws.call
        def root(op, *args, **kwargs):
            if op == 'get-caller-identity':
                return {'Account': ACCOUNT, 'Arn': 'arn:aws:iam::' + ACCOUNT + ':root'}
            return old(op, *args, **kwargs)
        self.aws.call = root
        with self.assertRaisesRegex(lab.LabError, 'NON_IAM'):
            obj.destroy()
        self.assertEqual(len(self.aws.mutations), count)

    def test_ambiguous_key_no_second_create_and_no_material_log(self):
        count = [0]
        def raw(*args, **kwargs):
            count[0] += 1
            return subprocess.CompletedProcess([], 255, '', 'fixture unknown response')
        self.aws.raw = raw
        self.obj.sleep = lambda _: (_ for _ in ()).throw(lab.LabError('FIXTURE_STOP_LIVE_WAIT'))
        output = io.StringIO()
        with patch('sys.stdout', output):
            with self.assertRaisesRegex(lab.LabError, 'FIXTURE_STOP'):
                self.obj.create()
        self.assertEqual(self.obj.state['status'], 'UNKNOWN')
        with self.assertRaisesRegex(lab.LabError, 'STATE_EXISTS'):
            self.obj.create()
        self.assertEqual(count[0], 1)
        self.assertNotIn('fixture unknown response', output.getvalue())
        self.assertNotIn('fixture-only', self.obj.path.read_text())

    def test_source_ip_change_blocks_actual_ingress(self):
        values = iter([SOURCE, SOURCE, str(lab.ipaddress.IPv4Address(0x08080404))])
        self.obj.ip_lookup = lambda: next(values)
        with self.assertRaisesRegex(lab.LabError, 'SOURCE_IP_CHANGED'):
            self.obj.create()
        self.assertNotIn('authorize-security-group-ingress', self.aws.mutations)
        self.assertNotIn(SOURCE, self.obj.path.read_text())

    def test_larger_ami_never_creates_or_falls_back(self):
        old = self.aws.call
        def large(op, *args, **kwargs):
            d = old(op, *args, **kwargs)
            if op == 'describe-images':
                d['Images'][0]['BlockDeviceMappings'][0]['Ebs']['VolumeSize'] = 16
            return d
        self.aws.call = large
        with self.assertRaisesRegex(lab.LabError, 'NO_FALLBACK'):
            self.obj.create()
        self.assertEqual(self.aws.mutations, [])

    def test_success_response_missing_id_keeps_unknown_pending(self):
        old = self.aws.call
        def missing(op, *args, **kwargs):
            result = old(op, *args, **kwargs)
            if op == 'create-vpc' and not kwargs.get('dry'):
                return {'Vpc': {}}
            return result
        self.aws.call = missing
        with self.assertRaises(KeyError):
            self.obj.create()
        disk = json.loads(self.obj.path.read_text())
        self.assertEqual(disk['status'], 'UNKNOWN')
        self.assertEqual(disk['pending_operation'], 'create-vpc')
        with self.assertRaisesRegex(lab.LabError, 'STATE_EXISTS'):
            self.obj.create()
        self.assertEqual(self.aws.mutations.count('create-vpc'), 1)

    def test_detached_volume_fallback_only_once_during_consistency_delay(self):
        obj = self.create()
        old = self.aws.call
        held = {}
        reads = [0]
        requested = [False]
        def delayed(op, args=(), **kwargs):
            if op == 'terminate-instances' and not kwargs.get('dry'):
                volume = copy.deepcopy(self.aws.db['volume'])
                result = old(op, args, **kwargs)
                volume.update(State='available', Attachments=[])
                self.aws.db['volume'] = volume
                return result
            if op == 'delete-volume' and not kwargs.get('dry'):
                self.aws.mutations.append(op)
                requested[0] = True
                return {}
            if op == 'describe-volumes' and requested[0]:
                reads[0] += 1
                if reads[0] >= 3:
                    self.aws.db.pop('volume', None)
            return old(op, args, **kwargs)
        self.aws.call = delayed
        obj.destroy()
        self.assertEqual(self.aws.mutations.count('delete-volume'), 1)
        self.assertGreaterEqual(reads[0], 3)

    def test_no_state_or_private_path_traversal(self):
        with self.assertRaisesRegex(lab.LabError, 'TRAVERSAL'):
            lab.secure_path(self.root / 'runtime/../../outside', self.root / 'runtime')
        target = self.root / 'runtime/link'
        target.symlink_to(self.root)
        with self.assertRaisesRegex(lab.LabError, 'SYMLINK'):
            lab.secure_path(target / 'state.json', self.root / 'runtime')


class TransportTests(unittest.TestCase):
    def test_ip_only_stdin_not_argv_or_events(self):
        calls = []
        def runner(argv, **kwargs):
            calls.append((argv, kwargs))
            return subprocess.CompletedProcess(argv, 0, '{}', '')
        aws = lab.AWS('fixture', lab.REGION, runner)
        aws.call('authorize-security-group-ingress', payload={'IpPermissions': [{'IpRanges': [{'CidrIp': SOURCE + '/32'}]}]})
        argv, kwargs = calls[0]
        self.assertNotIn(SOURCE, ' '.join(argv))
        self.assertIn(SOURCE, kwargs['input'])
        self.assertIn('file:///dev/stdin', argv)
        self.assertNotIn(SOURCE, json.dumps(aws.events))

    def test_exact_notfound_never_access_denied_or_timeout(self):
        for op, code, missing in [('describe-key-pairs', 'InvalidKeyPair.NotFound', True),
                                  ('describe-key-pairs', 'AccessDenied', False),
                                  ('describe-key-pairs', 'RequestTimeout', False),
                                  ('describe-volumes', 'InvalidKeyPair.NotFound', False)]:
            def runner(argv, **kwargs):
                return subprocess.CompletedProcess(argv, 254, '', 'An error occurred (' + code + ')')
            aws = lab.AWS('fixture', lab.REGION, runner)
            if missing:
                self.assertIsNone(aws.call(op, absent=True))
            else:
                with self.assertRaises(lab.LabError):
                    aws.call(op, absent=True)

    def test_key_missing_optional_type_durable_without_logging(self):
        sink = io.BytesIO()
        attempts = [0]
        def write(fd, value):
            attempts[0] += 1
            if attempts[0] == 1:
                raise InterruptedError()
            return sink.write(value[:3])
        raw = json.dumps({'KeyMaterial': 'fixture-only-not-a-key', 'KeyPairId': 'fixture-id'})
        output = io.StringIO()
        with patch('sys.stdout', output):
            result = lab.persist_key_response(raw, -1, write, lambda _: None, lambda _: None)
        self.assertEqual(sink.getvalue(), b'fixture-only-not-a-key')
        self.assertEqual(result['id'], 'fixture-id')
        self.assertEqual(output.getvalue(), '')

    def test_optimized_interpreter_rejected_without_aws(self):
        result = subprocess.run([sys.executable, '-O', str(Path(__file__).parents[1] / 'scripts/lab.py'), 'create'],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('OPTIMIZED_INTERPRETER_FORBIDDEN', result.stdout)


if __name__ == '__main__':
    unittest.main()
