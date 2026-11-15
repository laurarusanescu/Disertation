apiVersion: batch/v1
kind: Job
metadata:
  name: workload-__LEVEL__-__RUN_ID__
  namespace: eks-poc
  labels:
    app.kubernetes.io/name: eks-poc
    app.kubernetes.io/component: workload
    poc.run-id: "__RUN_ID__"
    poc.workload-level: "__LEVEL__"
spec:
  parallelism: __REPLICAS__
  completions: __REPLICAS__
  backoffLimit: 0
  activeDeadlineSeconds: __ACTIVE_DEADLINE_SECONDS__
  template:
    metadata:
      labels:
        app.kubernetes.io/name: eks-poc
        app.kubernetes.io/component: workload
        poc.run-id: "__RUN_ID__"
        poc.workload-level: "__LEVEL__"
    spec:
      restartPolicy: Never
      terminationGracePeriodSeconds: 10
      containers:
        - name: bounded-work
          image: public.ecr.aws/docker/library/python:3.13-alpine
          imagePullPolicy: IfNotPresent
          resources:
            requests:
              cpu: "__CPU_REQUEST__"
              memory: "__MEMORY_REQUEST__"
            limits:
              cpu: "__CPU_LIMIT__"
              memory: "__MEMORY_LIMIT__"
          env:
            - name: WORKLOAD_LEVEL
              value: "__LEVEL__"
            - name: RUN_ID
              value: "__RUN_ID__"
            - name: MAX_DURATION_SECONDS
              value: "__MAX_DURATION_SECONDS__"
            - name: INPUT_SIZE
              value: "__INPUT_SIZE__"
            - name: MEMORY_MB
              value: "__MEMORY_MB__"
            - name: CPU_WORKERS
              value: "__CPU_WORKERS__"
          command:
            - python
            - -c
            - |
              import hashlib
              import multiprocessing
              import os
              import time

              duration = int(os.environ["MAX_DURATION_SECONDS"])
              input_size = int(os.environ["INPUT_SIZE"])
              memory_mb = int(os.environ["MEMORY_MB"])
              workers = int(os.environ["CPU_WORKERS"])
              deadline = time.time() + duration
              payload = bytearray(memory_mb * 1024 * 1024)

              def burn(worker_index):
                  seed = f"{os.environ['RUN_ID']}:{worker_index}".encode()
                  digest = seed
                  iterations = 0
                  while time.time() < deadline and iterations < input_size:
                      digest = hashlib.sha256(digest + payload[:4096]).digest()
                      iterations += 1
                  return iterations

              with multiprocessing.Pool(processes=workers) as pool:
                  counts = pool.map(burn, range(workers))

              print({
                  "run_id": os.environ["RUN_ID"],
                  "level": os.environ["WORKLOAD_LEVEL"],
                  "workers": workers,
                  "input_size": input_size,
                  "memory_mb": memory_mb,
                  "iterations": sum(counts),
                  "duration_seconds": duration
              })
