import sys
import requests
import time
import os

# PROJECT_ID and JOB_ID are passed as arguments
project_id = f"{sys.argv[1]}"
job_id = f"{sys.argv[2]}"

# Get GITLAB_PAT from environment variable
gitlab_token = os.environ['GITLAB_PAT']

def parse_new_logs(new_logs, old_logs, last_line):
    try:
        new_logs = new_logs.split("\n")
    except:
        new_logs = []

    try:
        old_logs = old_logs.split("\n")
    except:
        old_logs = []

    # If the logs are the same, return an empty string
    if new_logs == old_logs:
        return ""
    
    # If the logs are different, return the new logs
    if len(new_logs) > len(old_logs):
        last_line = len(old_logs)
        return "\n".join(new_logs[last_line:])
    else:
        return "\n".join(new_logs)


def poll_gitlab_job(project_id, job_id, gitlab_token):
    headers = {
        'Private-Token': gitlab_token
    }
    logs_url = f"https://gitlab.com/api/v4/projects/{project_id}/jobs/{job_id}/trace"
    
    # Every 5 seconds, get the logs. Check for differences according to the last time and print the new logs
    last_line = 0
    old_logs = ""

    while True:
        logs = requests.get(logs_url, headers=headers).text

        if logs:
            if logs != old_logs:
                print(parse_new_logs(logs, old_logs, last_line))
                last_line = len(logs.split("\n"))
                logs = old_logs

            if "Job succeeded" in logs:
                print("Job succeeded")
                break
            elif "Job failed" in logs:
                print("Job failed")
                break

        time.sleep(5)




poll_gitlab_job(project_id, job_id, gitlab_token)
