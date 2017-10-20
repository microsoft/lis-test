from BaseHTTPServer import BaseHTTPRequestHandler, HTTPServer
import SocketServer
import logging
import json
import threading
import os
from utils import parse_results
from collections import defaultdict
from shutil import move

logger=logging.getLogger(__name__)

class PatchServerHandler(object):
    post_request_count = 0
    results = defaultdict(dict)
    expected_results = []
    expected_requests = 0
    builds_path = None
    failures_path = None

    @staticmethod
    def update(results, headers):
        for patch_name, result in results.items():
            PatchServerHandler.results[patch_name][headers['DISTRO']] = result 
        
        PatchServerHandler.post_request_count += 1
        logger.info(PatchServerHandler.results)
        

    @staticmethod
    def check():
        if PatchServerHandler.post_request_count == PatchServerHandler.expected_requests:
            for patch_name, results in PatchServerHandler.results.items():
                if patch_name in PatchServerHandler.expected_results:
                    if 'Failed' in results.values():
                        logger.warning('{} failed boot tests.'.format(patch_name))
                        move(
                            os.path.join(PatchServerHandler.builds_path, patch_name),
                            PatchServerHandler.failures_path
                        )
                    else:
                        logger.info('{} passed all boot tests.'.format(patch_name))
            return True
    
        return False 

class PatchServer(BaseHTTPRequestHandler):
    def _set_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()

    def do_GET(self):
        self._set_headers()
        self.wfile.write("<html><body><h1>Hello</h1></body></html>")

    def do_HEAD(self):
        self._set_headers()
        
    def do_POST(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        is_valid = self.check_request_data(post_data, self.headers)
        if not is_valid:
            self.send_error(400, 'Invalid message body')
        else:
            try:
                post_data = post_data.split('\r\n')
                test_results = parse_results(post_data)
                if test_results: PatchServerHandler.update(test_results, self.headers)
                self._set_headers()
            except KeyError:
                self.send_error('400', 'Invalid message structure')

    @staticmethod
    def check_request_data(data, headers):
        if headers['Content-Type'] != 'text/plain':
            return False
        return True

def start_server(handler, close_server, host='0.0.0.0', port=80):
    http_server = HTTPServer((host, port), handler)
    logger.info("Starting server on %s:%s" % (host, port))

    try:
        threading.Thread(target=http_server.serve_forever).start()
        while(not close_server()):
            pass
        http_server.shutdown()
    except KeyboardInterrupt:
        http_server.shutdown()

    http_server.server_close()
    logger.info("Stopping server on %s:%s" % (host, port))
