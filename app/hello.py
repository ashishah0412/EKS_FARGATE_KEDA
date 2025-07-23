# app/hello.py
from flask import Flask
import os
import time

app = Flask(__name__)

# Get hostname for demonstration purposes
HOSTNAME = os.uname()[1]

@app.route('/')
def hello():
    message = "Hello from {}! (Current time: {})".format(HOSTNAME, time.ctime())
    print(message) # Print to stdout, visible in pod logs
    return message

if __name__ == '__main__':
    # Listen on all public IPs, port 5000 as per common Docker practice
    app.run(host='0.0.0.0', port=5000)

