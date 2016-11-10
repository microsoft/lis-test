import os
import time
import creds
from pprint import pprint

import boto.ec2
from boto.manage.cmdshell import sshclient_from_instance

# TODO Add usage() and standalone script exec routines


def wait_for_state(obj, attr, state):
    print('Waiting for {} status {}'.format(str(obj), state))
    while getattr(obj, attr) != state:
        print('.')
        time.sleep(3)
        obj.update()
    print('done')


def wait_for_ping(instance_obj, local_path, key_name, username):
    ping_arg = '-n'
    if os.name == 'posix':
        ping_arg = '-c'
    if not instance_obj.public_dns_name:
        raise
    ping_cmd = 'ping {} 1 {}'.format(ping_arg, instance_obj.public_dns_name)
    try:
        timeout = 0
        while os.system(ping_cmd) != 0 or timeout >= 60:
            time.sleep(5)
            timeout += 5
        # artificial wait for ssh service up status
        time.sleep(30)
        client = sshclient_from_instance(instance_obj,
                                         os.path.join(local_path,
                                                      key_name + '.pem'),
                                         host_key_file='~\\ssh\\known_hosts',
                                         user_name=username)
    except Exception as e:
        print(e)
        client = None
    return client


def ec2_connect(region, local_path, key_name='test_ssh_key',
                group_name='test_sec_group'):
    conn = boto.ec2.connect_to_region(region,
                                      aws_access_key_id=creds.aws_access_key_id,
                                      aws_secret_access_key=
                                      creds.aws_secret_access_key)

    try:
        key_pair = conn.create_key_pair(key_name)
        key_pair.save(local_path)
    except conn.ResponseError as e:
        if e.code == 'InvalidKeyPair.Duplicate':
            print('KeyPair: %s already exists, using it.' % key_name)
        else:
            raise
    cidr = '0.0.0.0/0'
    try:
        group = conn.create_security_group(group_name, 'All access')
        group.authorize(ip_protocol='tcp', from_port=0, to_port=65535,
                        cidr_ip=cidr)
        group.authorize(ip_protocol='tcp', from_port=22, to_port=22,
                        cidr_ip=cidr)
        group.authorize(ip_protocol='udp', from_port=0, to_port=65535,
                        cidr_ip=cidr)
        group.authorize(ip_protocol='icmp', from_port=-1, to_port=-1,
                        cidr_ip=cidr)
    except conn.ResponseError as e:
        if e.code == 'InvalidGroup.Duplicate':
            print('Security Group: %s already exists, using it.' % group_name)
        elif e.code == 'InvalidPermission.Duplicate':
            print('Security Group: %s already authorized' % group_name)
        else:
            raise

    return conn


def attach_ebs_volume(conn, instance, zone, size=10):
    # Add EBS volume DONE
    ebs_vol = conn.create_volume(size, zone)
    wait_for_state(ebs_vol, 'status', 'available')
    conn.attach_volume(ebs_vol.id, instance.id, '/dev/sdx')
    return ebs_vol


def aws_create_instance(conn, inst_type, image_id, zone='eu-west-1a',
                        key_name='test_ssh_key', group_name='test_sec_group'):

    reservation = conn.run_instances(image_id,
                                     key_name=key_name,
                                     instance_type=inst_type,
                                     placement=zone,
                                     security_groups=[group_name],
                                     user_data=None
                                     )
    instance = reservation.instances[0]
    time.sleep(5)
    wait_for_state(instance, 'state', 'running')

    # artificial wait for public ip
    time.sleep(5)
    instance.update()
    pprint(instance.__dict__)

    return instance


def teardown(conn, instance, ebs_vol=None):
    # teardown
    if ebs_vol:
        conn.detach_volume(ebs_vol.id, instance.id, '/dev/sdx')
        conn.delete_volume(ebs_vol.id)
    conn.terminate_instances(instance_ids=[instance.id])


def run_orion():
    local_path = '~\\aws'
    key_name = 'test_ssh_key'
    region = 'eu-west-1'
    zone = 'eu-west-1a'
    inst_type = 'd2.4xlarge'
    # Ubuntu 16.04 ami
    image_id = 'ami-0d77397e'
    username = 'ubuntu'

    conn = ec2_connect(region, local_path, key_name='test_ssh_key',
                       group_name='test_sec_group')
    instance = aws_create_instance(conn, inst_type, image_id,
                                   zone='eu-west-1a',
                                   key_name='test_ssh_key',
                                   group_name='test_sec_group')

    ssh_client = wait_for_ping(instance, local_path, key_name, username)
    ebs_vol = attach_ebs_volume(conn, instance, zone, size=10)

    if ssh_client:
        pprint(ssh_client.put_file(
            "~\\aws\\orion_linux_x86-64.gz", "/tmp/orion_linux_x86-64.gz"))
        pprint(ssh_client.put_file(
            "tools\\aws\\run_orion.sh", "/tmp/run_orion.sh"))
        ssh_client.run('chmod +x /tmp/run_orion.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/run_orion.sh")
        ssh_client.run('/tmp/run_orion.sh')
        ssh_client.get_file('/tmp/orion.zip', "~\\aws\\orion.zip")

    teardown(conn, instance, ebs_vol)


def run_sysbench():
    local_path = '~\\aws'
    key_name = 'test_ssh_key'
    region = 'eu-west-1'
    inst_type = 'd2.4xlarge'
    # Ubuntu 16.04 ami
    image_id = 'ami-0d77397e'
    username = 'ubuntu'

    conn = ec2_connect(region, local_path, key_name='test_ssh_key',
                       group_name='test_sec_group')
    instance = aws_create_instance(conn, inst_type, image_id,
                                   zone='eu-west-1a',
                                   key_name='test_ssh_key',
                                   group_name='test_sec_group')
    ssh_client = wait_for_ping(instance, local_path, key_name, username)

    if ssh_client:
        ssh_client.put_file(
            "tools\\aws\\run_sysbench.sh", "/tmp/run_sysbench.sh")
        ssh_client.run('chmod +x /tmp/run_sysbench.sh')
        ssh_client.run("sed -i 's/\r//' /tmp/run_sysbench.sh")
        channel = ssh_client.run_pty('/tmp/run_sysbench.sh')
        stderr = ''
        read_err = channel.recv_stderr(1024)
        while read_err:
            stderr += read_err
            read_err = channel.recv_stderr(1024)
        print(stderr)

        ssh_client.get_file('/tmp/sysbench.zip', "~\\aws\\sysbench.zip")

    teardown(conn, instance)

if __name__ == '__main__':
    run_orion()
    # run_sysbench()
