from flask import Flask
app = Flask(__name__)

@app.route("/")
def hello():
    return "Hello World from Python app on EKS Fargate with KEDA!"

@app.route("/cpu")
def cpu_burn():
    import time
    start = time.time()
    while time.time() - start < 10:
        pass
    return "CPU load generated for 10 seconds"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

