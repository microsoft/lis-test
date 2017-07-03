import os
import logging
import ConfigParser

from sqlalchemy import Table, Column, Date, DECIMAL, INT, BIGINT, NVARCHAR, MetaData, create_engine
from sqlalchemy.pool import NullPool
from sqlalchemy.orm import create_session, mapper


logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)

COLUMNS = [{'name': 'TestCaseName', 'type': NVARCHAR(50)},
           {'name': 'DataPath', 'type': NVARCHAR(10)},
           {'name': 'TestDate', 'type': Date},
           {'name': 'HostBy', 'type': NVARCHAR(50)},
           {'name': 'HostOS', 'type': NVARCHAR(100)},
           {'name': 'HostType', 'type': NVARCHAR(50)},
           {'name': 'InstanceSize', 'type': NVARCHAR(20)},
           {'name': 'GuestOS', 'type': NVARCHAR(50)},
           {'name': 'GuestSize', 'type': NVARCHAR(50)},
           {'name': 'GuestOSType', 'type': NVARCHAR(50)},
           {'name': 'GuestDistro', 'type': NVARCHAR(50)},
           {'name': 'KernelVersion', 'type': NVARCHAR(30)},
           {'name': 'DiskSetup', 'type': NVARCHAR(20)},
           {'name': 'TestMode', 'type': NVARCHAR(30)},
           {'name': 'FileTestMode', 'type': NVARCHAR(20)},
           {'name': 'WebServerVersion', 'type': NVARCHAR(20)},
           {'name': 'Driver', 'type': NVARCHAR(10)},
           {'name': 'IPVersion', 'type': NVARCHAR(4)},
           {'name': 'ProtocolType', 'type': NVARCHAR(3)},
           {'name': 'ClusterSetup', 'type': NVARCHAR(25)},
           {'name': 'HadoopVersion', 'type': NVARCHAR(12)},
           {'name': 'Threads', 'type': DECIMAL(4, 0)},
           {'name': 'TestConnections', 'type': DECIMAL(4, 0)},
           {'name': 'NumberOfConnections', 'type': INT},
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
           {'name': 'BlockSize_KB', 'type': INT},
           {'name': 'QDepth', 'type': INT},
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
           {'name': 'Throughput_Gbps', 'type': DECIMAL(5, 3)},
           {'name': 'Latency_ms', 'type': DECIMAL(9, 3)},
           {'name': 'PacketSize_KBytes', 'type': DECIMAL(5, 3)},
           {'name': 'MaxLatency_us', 'type': DECIMAL(9, 3)},
           {'name': 'AverageLatency_us', 'type': DECIMAL(9, 3)},
           {'name': 'MinLatency_us', 'type': DECIMAL(9, 3)},
           {'name': 'Latency95Percentile_us', 'type': DECIMAL(9, 3)},
           {'name': 'Latency99Percentile_us', 'type': DECIMAL(9, 3)},
           {'name': 'seq_read_iops', 'type': DECIMAL(8, 1)},
           {'name': 'seq_read_lat_usec', 'type': DECIMAL(10, 2)},
           {'name': 'rand_read_iops', 'type': DECIMAL(8, 1)},
           {'name': 'rand_read_lat_usec', 'type': DECIMAL(10, 2)},
           {'name': 'seq_write_iops', 'type': DECIMAL(8, 1)},
           {'name': 'seq_write_lat_usec', 'type': DECIMAL(10, 2)},
           {'name': 'rand_write_iops', 'type': DECIMAL(8, 1)},
           {'name': 'rand_write_lat_usec', 'type': DECIMAL(10, 2)},
           ]


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

    # When creating db is also necessary
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
