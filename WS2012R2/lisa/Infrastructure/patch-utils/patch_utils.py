import sys
import logging
from config import get_arg_parser
from patch_manager import PatchManager

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main(arguments):
    parser = get_arg_parser()
    logger.info('Running %s command' % arguments[0])
    manager = PatchManager(
        arguments[0], parser.parse_args(arguments)
    )
    manager()

if __name__ == '__main__':
    main(sys.argv[1:])
