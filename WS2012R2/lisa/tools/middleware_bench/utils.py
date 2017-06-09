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
