import base64
import json
import logging
import os
import secrets
import string

import pg8000.native
from google.cloud import secretmanager

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
DB_HOST = os.environ.get('DB_HOST', '10.0.0.250')
DB_PORT = os.environ.get('DB_PORT', '5432')
DB_USER_SECRET = os.environ.get('DB_USER_SECRET')
DB_NAME_SECRET = os.environ.get('DB_NAME_SECRET')

client = secretmanager.SecretManagerServiceClient()

def get_secret(secret_name):
    """Retrieve the secret value from Secret Manager."""
    response = client.access_secret_version(request={"name": secret_name})
    return response.payload.data.decode("UTF-8")

def add_secret_version(secret_name, payload):
    """Add a new version to the Secret Manager secret."""
    parent = client.secret_path(client.parse_secret_path(secret_name)['project'], client.parse_secret_path(secret_name)['secret'])
    payload_bytes = payload.encode("UTF-8")
    response = client.add_secret_version(
        request={
            "parent": parent,
            "payload": {"data": payload_bytes},
        }
    )
    return response.name

def generate_password(length=20):
    """Generate a random strong password."""
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for i in range(length))

import functions_framework

@functions_framework.cloud_event
def rotate_postgres_password(cloud_event):
    """Triggered from a message on a Cloud Pub/Sub topic.
    Args:
         cloud_event (functions_framework.CloudEvent): The CloudEvent.
    """
    pubsub_message = base64.b64decode(cloud_event.data["message"]["data"]).decode('utf-8')
    logger.info(f"Received message: {pubsub_message}")
    
    # Secret Manager sends the secret version name in the message
    # e.g. "projects/12345/secrets/my-secret/versions/1"
    # Actually, Secret Manager rotation notifications payload usually contains
    # the JSON string with "name" which is the secret name.
    
    try:
        data = json.loads(pubsub_message)
        secret_name = data.get('name') # e.g. "projects/123/secrets/my-secret"
        event_type = data.get('eventType')
        
        if event_type != "SECRET_ROTATE":
             logger.info(f"Ignoring event type: {event_type}")
             return "OK"
             
        if not secret_name:
             logger.error("No secret name provided in event payload")
             return "Error"
             
        logger.info(f"Rotating secret: {secret_name}")
        
        # Get current user and database names
        db_user = get_secret(f"{DB_USER_SECRET}/versions/latest")
        db_name = get_secret(f"{DB_NAME_SECRET}/versions/latest")
        
        # Get current password
        current_password = get_secret(f"{secret_name}/versions/latest")
        
        # Connect to Postgres
        logger.info(f"Connecting to Postgres at {DB_HOST}:{DB_PORT} as {db_user}")
        con = pg8000.native.Connection(
            user=db_user,
            password=current_password,
            host=DB_HOST,
            port=int(DB_PORT),
            database=db_name
        )
        
        # Generate new password
        new_password = generate_password()
        
        # Update Postgres password
        logger.info("Updating password in Postgres")
        # Ensure the user name is safely escaped if necessary, 
        # but here we use the safe native param binding.
        con.run(f"ALTER USER {db_user} WITH PASSWORD '{new_password}';")
        con.close()
        
        # Save new password to Secret Manager
        logger.info("Saving new password to Secret Manager")
        new_version_name = add_secret_version(secret_name, new_password)
        logger.info(f"Created new secret version: {new_version_name}")
        
        return "Success"

    except Exception as e:
        logger.error(f"Rotation failed: {str(e)}")
        raise
