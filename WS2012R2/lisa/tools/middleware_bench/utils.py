import constants
import logging

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
        return 'hvm'
    elif provider == constants.AZURE:
        return 'MS Azure'
    elif provider == constants.GCE:
        return 'kvm'


