import constants
import logging

from winrm import protocol

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


def host_type(provider):
    """
    Return host type by provider
    :param provider: cloud provider
    :return: Host type string
    """
    if provider == constants.AWS:
        return constants.HVM
    elif provider == constants.AZURE:
        return constants.MSAZURE
    elif provider == constants.GCE:
        return constants.KVM


def data_path(sriov):
    """
    Return data path based on sriov state
    :param sriov: sriov state
    :return: Data path string
    """
    if sriov == constants.ENABLED:
        return constants.SRIOV
    else:
        return constants.SYNTHETIC


def run_sql(sql, server, db=None, user=None, password=None):
    """
    Return SQL command to run on Windows
    :param sql: sql file script
    :param server: server instance
    :param user: db user
    :param password: db password
    :param db: database to execute sql on
    :return: SQL command
    """
    if not user:
        user = constants.MSSQL_USER
    cmd = 'Invoke-Sqlcmd -InputFile \'{}\' -ServerInstance {} -Username {} -Password {}'.format(
            sql, server, user, password)
    if db:
        cmd += ' -Database {}'.format(db)
    return cmd


def run_win_command(cmd=None, host=None, user=None, password=None, ps=False):
    """
    Run Windows remote command.
    :param cmd: Windows command to run
    :param host: Windows host to run command
    :param user: Windows username
    :param password: windows password
    :param ps: <bool> to run powershell command instead
    :return: std_out, std_err, exit_code
    """
    if not cmd or not host:
        log.error('Please provide command and host to run remotely.')
    if ps:
        cmd = 'powershell -NoProfile -NonInteractive ' + cmd
    port = 5986
    proto = 'https'
    secure_host = '{}://{}:{}/wsman'.format(proto, host, port)

    protocol.Protocol.DEFAULT_TIMEOUT = "PT7200S"
    try:
        p = protocol.Protocol(endpoint=secure_host, transport='ssl',
                              username=user, password=password,
                              server_cert_validation='ignore')
        shell_id = p.open_shell()
        command_id = p.run_command(shell_id, cmd)
        std_out, std_err, exit_code = p.get_command_output(shell_id, command_id)
        log.info('Output: {}'.format(std_out))
        log.debug('Output: {}\nError: {}\nExit Code: {}'.format(std_out, std_err, exit_code))
        if exit_code != 0:
            log.error('{}.\nFailed to run command: {}'.format(std_err, cmd))
        p.cleanup_command(shell_id, command_id)
        p.close_shell(shell_id)
    except Exception as e:
        log.error(e)
        raise
    return std_out

