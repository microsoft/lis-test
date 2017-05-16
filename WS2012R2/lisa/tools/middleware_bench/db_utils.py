import os
import logging
import ConfigParser

from sqlalchemy import Table, Column, Date, DECIMAL, BIGINT, NVARCHAR, MetaData, create_engine
from sqlalchemy.pool import NullPool
from sqlalchemy.orm import create_session, mapper


logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)

COLUMNS = [{'name': 'TestCaseName', 'type': NVARCHAR(50)},
           {'name': 'TestDate', 'type': Date},
           {'name': 'HostType', 'type': NVARCHAR(10)},
           {'name': 'InstanceSize', 'type': NVARCHAR(20)},
           {'name': 'GuestOS', 'type': NVARCHAR(30)},
           {'name': 'KernelVersion', 'type': NVARCHAR(30)},
           {'name': 'DiskSetup', 'type': NVARCHAR(20)},
           {'name': 'TestMode', 'type': NVARCHAR(30)},
           {'name': 'FileTestMode', 'type': NVARCHAR(20)},
           {'name': 'ApacheVersion', 'type': NVARCHAR(20)},
           {'name': 'Driver', 'type': NVARCHAR(10)},
           {'name': 'ClusterSetup', 'type': NVARCHAR(25)},
           {'name': 'HadoopVersion', 'type': NVARCHAR(12)},
           {'name': 'Threads', 'type': DECIMAL(4, 0)},
           {'name': 'TestConnections', 'type': DECIMAL(4, 0)},
           {'name': 'TestPipelines', 'type': DECIMAL(4, 0)},
           {'name': 'TestConcurrency', 'type': DECIMAL(4, 0)},
           {'name': 'NodeSize_bytes', 'type': DECIMAL(4, 0)},
           {'name': 'TeragenRecords', 'type': DECIMAL(12, 0)},
           {'name': 'SortDuration_sec', 'type': DECIMAL(10, 4)},
           {'name': 'TotalCreatedCallsPerSec', 'type': DECIMAL(10, 4)},
           {'name': 'TotalSetCallsPerSec', 'type': DECIMAL(10, 4)},
           {'name': 'TotalGetCallsPerSec', 'type': DECIMAL(10, 4)},
           {'name': 'TotalDeletedCallsPerSec', 'type': DECIMAL(10, 4)},
           {'name': 'TotalWatchedCallsPerSec', 'type': DECIMAL(10, 4)},
           {'name': 'TotalQueries', 'type': DECIMAL(9, 0)},
           {'name': 'TransactionsPerSec', 'type': DECIMAL(8, 3)},
           {'name': 'DeadlocksPerSec', 'type': DECIMAL(8, 3)},
           {'name': 'RWRequestsPerSec', 'type': DECIMAL(10, 3)},
           {'name': 'NumberOfAbInstances', 'type': DECIMAL(3, 0)},
           {'name': 'ConcurrencyPerAbInstance', 'type': DECIMAL(3, 0)},
           {'name': 'Document_bytes', 'type': DECIMAL(7, 0)},
           {'name': 'CompleteRequests', 'type': DECIMAL(7, 0)},
           {'name': 'RequestsPerSec', 'type': DECIMAL(8, 3)},
           {'name': 'TransferRate_KBps', 'type': DECIMAL(10, 3)},
           {'name': 'MeanConnectionTimes_ms', 'type': DECIMAL(8, 4)},
           {'name': 'TotalRequests', 'type': DECIMAL(9, 0)},
           {'name': 'ParallelClients', 'type': DECIMAL(5, 0)},
           {'name': 'Payload_bytes', 'type': DECIMAL(5, 0)},
           {'name': 'ConnectionsPerThread', 'type': DECIMAL(8, 0)},
           {'name': 'RequestsPerThread', 'type': DECIMAL(8, 0)},
           {'name': 'BestLatency_ms', 'type': DECIMAL(7, 4)},
           {'name': 'WorstLatency_ms', 'type': DECIMAL(7, 4)},
           {'name': 'AverageLatency_ms', 'type': DECIMAL(7, 4)},
           {'name': 'BestOpsPerSec', 'type': DECIMAL(10, 3)},
           {'name': 'WorstOpsPerSec', 'type': DECIMAL(10, 3)},
           {'name': 'AverageOpsPerSec', 'type': DECIMAL(10, 3)},
           {'name': 'SETRequestsPerSec', 'type': DECIMAL(10, 3)},
           {'name': 'GETRequestsPerSec', 'type': DECIMAL(10, 3)},
           {'name': 'NumOutstandingSmall_IO', 'type': DECIMAL(3, 0)},
           {'name': 'NumOutstandingLarge_IO', 'type': DECIMAL(3, 0)},
           {'name': 'BlockSize_Kb', 'type': DECIMAL(3, 0)},
           {'name': 'Throughput_MBps', 'type': DECIMAL(10, 2)},
           {'name': 'Latency95Percentile_ms', 'type': DECIMAL(10, 2)},
           {'name': 'RequestsExecutedPerSec', 'type': DECIMAL(10, 2)},
           {'name': 'Latency_ms', 'type': DECIMAL(7, 3)},
           {'name': 'IOPS', 'type': DECIMAL(10, 2)},
           {'name': 'TotalOpsPerSec', 'type': DECIMAL(10, 4)},
           {'name': 'ReadOps', 'type': DECIMAL(9, 1)},
           {'name': 'ReadLatency95Percentile_us', 'type': DECIMAL(6, 0)},
           {'name': 'CleanupOps', 'type': DECIMAL(9, 1)},
           {'name': 'CleanupLatency95Percentile_us', 'type': DECIMAL(6, 0)},
           {'name': 'UpdateOps', 'type': DECIMAL(9, 1)},
           {'name': 'UpdateLatency95Percentile_us', 'type': DECIMAL(6, 0)},
           {'name': 'ReadFailedOps', 'type': DECIMAL(9, 1)},
           {'name': 'ReadFailedLatency95Percentile_us', 'type': DECIMAL(6, 0)},
           ]

# Base = declarative_base()


class TestResults(object):
    def __getitem__(self, item):
        return getattr(self, item)

    def __setitem__(self, item, value):
        return setattr(self, item, value)


def upload_results(localpath=None, table_name=None, results_path=None, parser=None, **kwargs):

    if localpath:
        log.info('Looking up DB credentials for results upload in {}.' .format(localpath))
        db_creds_file = [os.path.join(localpath, c) for c in os.listdir(localpath)
                         if c.endswith('.config')][0]
        # read credentials from file - should be present in the localpath provided to runner
        config = ConfigParser.ConfigParser()
        config.read(db_creds_file)
    else:
        log.error('No credentials file path provided. Skipping results upload.')
        return None

    test_results = parser(log_path=results_path, **kwargs).process_logs()

    e = create_engine('mssql+pyodbc://{}:{}@{}/{}?driver={}'.format(
            config.get('Credentials', 'User'), config.get('Credentials', 'Password'),
            config.get('Credentials', 'Server'), config.get('Credentials', 'Database'),
            config.get('Credentials', 'Driver'), poolclass=NullPool, echo=True))
    metadata = MetaData(bind=e)

    table_columns = [column for column in COLUMNS if column['name'] in test_results[0]]
    t = Table(table_name, metadata,
              Column('TestId', BIGINT, primary_key=True, nullable=False, index=True),
              *(Column(column['name'], column['type']) for column in table_columns))

    # metadata.create_all(checkfirst=True)
    mapper(TestResults, t)
    session = create_session(bind=e, autocommit=False, autoflush=True)

    for row in test_results:
        test_data = TestResults()
        for key, value in row.items():
            test_data[key] = value
        session.add(test_data)
        try:
            session.commit()
        except:
            print("Failed to commit {} data. Rolling back.".format(row))
            session.rollback()
            raise


if __name__ == '__main__':
    print('starting')
    lo_path = "C:\\Users\Mihai Costache\\Desktop\\sysbench1490684898.86_Standard_DS14_v2.zip"
    creds = "C:\Users\Mihai Costache\Desktop\Cloudbase\middleware_benchmark\middleware_bench.config"
    test_case_name = 'Azure_Sysbench_fileio_perf_tuned_noSRIOV'
    guest_os = 'Ubuntu 16.04'
    host_type = 'MS Azure'
    instance_size = 'Standard_DS14_v2'
    disk_setup = '1 x SSD 513 GB'
    from results_parser import SysbenchLogsReader
    upload_results(localpath=creds, table_name='Test', results_path=lo_path,
                   parser=SysbenchLogsReader,
                   test_case_name=test_case_name, guest_os=guest_os, host_type=host_type,
                   instance_size=instance_size, disk_setup=disk_setup)

