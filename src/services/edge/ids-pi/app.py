#!/usr/bin/env python3

import os
import sys
import time
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class IDSPiHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {"status": "healthy", "service": "ids-pi", "mode": os.getenv('SERVICE_MODE', 'edge')}
            self.wfile.write(json.dumps(response).encode())
        elif self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                "service": "IDS-Pi Edge Security Service",
                "status": "running",
                "mode": os.getenv('SERVICE_MODE', 'edge')
            }
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        logger.info(format % args)

def main():
    port = int(os.getenv('IDS_PI_PORT', os.getenv('SERVICE_PORT', '8080')))
    host = '0.0.0.0'
    
    logger.info(f"Starting IDS-Pi Edge Security Service on {host}:{port}")
    logger.info(f"Service mode: {os.getenv('SERVICE_MODE', 'edge')}")
    
    try:
        server = HTTPServer((host, port), IDSPiHandler)
        logger.info("IDS-Pi service started successfully")
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Shutting down IDS-Pi service")
        server.shutdown()
    except Exception as e:
        logger.error(f"Failed to start IDS-Pi service: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
