from http.server import HTTPServer, BaseHTTPRequestHandler
import psycopg2
import os
import sys

class HealthCheckHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/healthz':
            try:
                # Check database connection
                conn = psycopg2.connect(
                    host=os.getenv('DB_HOST'),
                    port=os.getenv('DB_PORT', 5432),
                    database=os.getenv('DB_NAME'),
                    user=os.getenv('DB_USERNAME'),
                    password=os.getenv('DB_PASSWORD'),
                    connect_timeout=5
                )
                conn.close()
                
                self.send_response(200)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(b'OK')
            except Exception as e:
                self.send_response(503)
                self.send_header('Content-type', 'text/plain')
                self.end_headers()
                self.wfile.write(f'ERROR: {str(e)}'.encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8502), HealthCheckHandler)
    print('Health check server started on port 8502')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nShutting down health check server')
        server.shutdown()

# Made with Bob
