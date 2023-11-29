import requests
import os
import json
import time


if __name__ == "__main__":
    # Get home directory
    home_dir = os.path.expanduser("~")
    info_file_path = os.path.join(home_dir, "server_info.txt")

    # Read IP address and port from a file
    with open(info_file_path, "r") as file:
        ip_address = file.readline().split(":")[1].strip()
        port = file.readline().split(":")[1].strip()
        hostname = file.readline().split(":")[1].strip()

    ip_address = hostname

    # Wait a min to ensure the server is running
    while True:
        try:
            response = requests.get(f"http://{ip_address}:{port}/")
            break
        except:  # noqa any error is fine for now
            time.sleep(60)

    # get the PBS_ARRAY_INDEX
    pbs_array_index = os.environ['PBS_ARRAY_INDEX']
    print(f"PBS_ARRAY_INDEX: {pbs_array_index}")
    # if the PBS_ARRAY_INDEX is empty, set it to 'FNAR'
    if pbs_array_index == "":
        pbs_array_index = "FNAR"

    # Create a message
    message = {
        "sender_id": "client_" + pbs_array_index + "_" + str(time.time()),
        "receiver_id": "client_2",
        "message": "Hello World!"
    }

    # Encode the message as JSON
    message = json.dumps(message)
    # Set the headers
    headers = {'Content-type': 'application/json'}

    # Send the message to the server
    response = requests.post(f"http://{ip_address}:{port}/", data=message, headers=headers)
    print(response.text)

    # Get the message queue from the server
    response = requests.get(f"http://{ip_address}:{port}/")
    # Decode the message queue from JSON
    message_queue = json.loads(response.text)
    print(message_queue)
