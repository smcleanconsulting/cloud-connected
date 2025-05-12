import base64
import json
import os
import logging
import datetime
import functions_framework
import re
from googleapiclient import discovery
from google.oauth2 import service_account

# Set up structured logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def detach_billing(cloud_event):
    """Process a Pub/Sub message about budget alerts and detach billing if conditions are met.
    
    Args:
        cloud_event: A CloudEvent containing the Pub/Sub message data.
    """
    # Add extensive logging at the start
    print("FUNCTION STARTED: detach_billing function triggered")
    logger.info("FUNCTION STARTED: detach_billing function triggered")
    
    # Log the cloud event details
    print(f"Cloud event type: {type(cloud_event)}")
    print(f"Cloud event attributes: {dir(cloud_event)}")
    logger.info(f"Cloud event type: {type(cloud_event)}")
    logger.info(f"Cloud event received: {str(cloud_event)}")
    
    try:
        # Log if cloud_event has data attribute
        has_data = hasattr(cloud_event, 'data')
        print(f"Has data attribute: {has_data}")
        logger.info(f"Has data attribute: {has_data}")
        
        # Extract the Pub/Sub message data
        if not has_data or not cloud_event.data:
            error_msg = "Cloud event contains no data"
            print(error_msg)
            logger.warning(error_msg)
            return

        # The Pub/Sub message is contained in the data field of the CloudEvent
        print(f"Cloud event data: {cloud_event.data}")
        logger.info(f"Cloud event data: {cloud_event.data}")
        
        pub_sub_message = cloud_event.data.get('message', {})
        print(f"Pub/Sub message: {pub_sub_message}")
        logger.info(f"Pub/Sub message: {pub_sub_message}")
        
        # The message data is base64-encoded
        if 'data' not in pub_sub_message:
            error_msg = "No data field in Pub/Sub message"
            print(error_msg)
            logger.warning(error_msg)
            return
            
        message_data = base64.b64decode(pub_sub_message['data']).decode('utf-8')
        print(f"Decoded message: {message_data}")
        logger.info(f"Decoded message: {message_data}")
        
        # Parse the JSON payload, being careful about format
        try:
            # Try to parse as valid JSON
            budget_notification = json.loads(message_data)
            print(f"Budget notification: {budget_notification}")
            logger.info(f"Budget notification: {budget_notification}")
        except json.JSONDecodeError as e:
            error_msg = f"Failed to parse message as JSON: {e}"
            print(error_msg)
            logger.error(error_msg)
            
            # Fallback: just try to extract projectId if it appears in the message
            if "projectId" in message_data:
                match = re.search(r'projectId["\s:=]+([^,"}\s]+)', message_data)
                if match:
                    project_id = match.group(1)
                    print(f"Extracted project ID using regex: {project_id}")
                    logger.info(f"Extracted project ID using regex: {project_id}")
                    
                    # Create a simplified budget notification
                    budget_notification = {
                        "costAmount": 9999, # High value to ensure condition is met
                        "budgetAmount": 100,
                        "projectId": project_id
                    }
                else:
                    error_msg = "Could not extract project ID from malformed message"
                    print(error_msg)
                    logger.error(error_msg)
                    return
            else:
                error_msg = "No project ID found in message"
                print(error_msg)
                logger.error(error_msg)
                return
            
        # Process the budget notification
        process_budget_notification(budget_notification)
            
    except Exception as e:
        error_msg = f"Error processing cloud event: {e}"
        print(error_msg)
        logger.error(error_msg, exc_info=True)
        raise

def process_budget_notification(budget_notification):
    """Process the budget notification and detach billing if conditions are met."""
    print("FUNCTION: process_budget_notification started")
    logger.info("FUNCTION: process_budget_notification started")
    
    try:
        # Extract relevant data from the budget notification
        cost_amount = budget_notification.get('costAmount')
        budget_amount = budget_notification.get('budgetAmount')
        
        print(f"Cost amount: {cost_amount}, Budget amount: {budget_amount}")
        logger.info(f"Cost amount: {cost_amount}, Budget amount: {budget_amount}")
        
        # Either use alertThresholdExceeded or calculate from the amounts
        alert_threshold_exceeded = budget_notification.get('alertThresholdExceeded')
        if alert_threshold_exceeded is None and cost_amount and budget_amount:
            alert_threshold_exceeded = cost_amount / budget_amount
            
        print(f"Alert threshold exceeded: {alert_threshold_exceeded}")
        logger.info(f"Alert threshold exceeded: {alert_threshold_exceeded}")
            
        # Extract project ID
        project_id = budget_notification.get('projectId')
        if not project_id:
            error_msg = "Could not determine project ID from notification"
            print(error_msg)
            logger.error(error_msg)
            return
            
        print(f"Processing budget alert for project {project_id}")
        logger.info(f"Processing budget alert for project {project_id}")
        
        # Define your conditions for detaching billing
        should_detach = evaluate_detach_conditions(
            cost_amount, 
            budget_amount, 
            alert_threshold_exceeded,
            project_id
        )
        
        print(f"Should detach billing: {should_detach}")
        logger.info(f"Should detach billing: {should_detach}")
        
        if should_detach:
            result = detach_billing_account(project_id)
            print(f"Billing detachment result: {result}")
            logger.info(f"Billing detachment result: {result}")
        else:
            print(f"Conditions not met for detaching billing from project {project_id}")
            logger.info(f"Conditions not met for detaching billing from project {project_id}")
            
    except Exception as e:
        error_msg = f"Error processing budget notification: {e}"
        print(error_msg)
        logger.error(error_msg, exc_info=True)
        raise

def evaluate_detach_conditions(cost_amount, budget_amount, alert_threshold_exceeded, project_id):
    """
    Evaluate whether billing should be detached based on your specific conditions.
    """
    print("FUNCTION: evaluate_detach_conditions started")
    logger.info("FUNCTION: evaluate_detach_conditions started")
    
    # Get exclusion list from environment variable
    exclusion_list = [p.strip() for p in os.environ.get('EXCLUSION_LIST', '').split(',') if p.strip()]
    print(f"Exclusion list: {exclusion_list}")
    logger.info(f"Exclusion list: {exclusion_list}")
    
    # Get allowed overage percentage from environment variable (default to 10%)
    allowed_overage_pct = float(os.environ.get('ALLOWED_OVERAGE_PCT', '10'))
    max_threshold = 1.0 + (allowed_overage_pct / 100)
    print(f"Allowed overage percentage: {allowed_overage_pct}%, Max threshold: {max_threshold}")
    logger.info(f"Allowed overage percentage: {allowed_overage_pct}%, Max threshold: {max_threshold}")
    
    # Check conditions
    is_exceeding_threshold = alert_threshold_exceeded >= max_threshold
    is_in_exclusion_list = project_id in exclusion_list
    
    print(f"Is exceeding threshold: {is_exceeding_threshold}")
    print(f"Is in exclusion list: {is_in_exclusion_list}")
    logger.info(f"Is exceeding threshold: {is_exceeding_threshold}, Is in exclusion list: {is_in_exclusion_list}")
    
    # Example condition: Detach if threshold exceeded by more than allowed overage and not in exclusion list
    if (is_exceeding_threshold and not is_in_exclusion_list):
        print(f"Condition met: Threshold {alert_threshold_exceeded} exceeds max allowed {max_threshold}")
        logger.info(f"Condition met: Threshold {alert_threshold_exceeded} exceeds max allowed {max_threshold}")
        return True
    
    if not is_exceeding_threshold:
        print(f"Condition not met: Threshold {alert_threshold_exceeded} does not exceed max allowed {max_threshold}")
        logger.info(f"Condition not met: Threshold {alert_threshold_exceeded} does not exceed max allowed {max_threshold}")
    
    if is_in_exclusion_list:
        print(f"Condition not met: Project {project_id} is in exclusion list")
        logger.info(f"Condition not met: Project {project_id} is in exclusion list")
    
    return False

def detach_billing_account(project_id):
    """
    Detach billing account from the specified project.
    This implementation actually detaches the billing account.
    """
    print("FUNCTION: detach_billing_account started - WILL ACTUALLY DETACH BILLING")
    logger.info("FUNCTION: detach_billing_account started - WILL ACTUALLY DETACH BILLING")
    
    try:
        # Use the Cloud Billing API to detach billing
        service = discovery.build('cloudbilling', 'v1', cache_discovery=False)
        
        # Format the project name
        name = f'projects/{project_id}'
        
        print(f"Getting current billing info for project {project_id}")
        logger.info(f"Getting current billing info for project {project_id}")
        
        try:
            # Get current billing info to log it
            billing_info = service.projects().getBillingInfo(name=name).execute()
            current_billing_account = billing_info.get('billingAccountName', 'Not found')
            print(f"Current billing account for project {project_id}: {current_billing_account}")
            logger.info(f"Current billing account for project {project_id}: {current_billing_account}")
        except Exception as e:
            print(f"Could not get current billing info: {e}")
            logger.warning(f"Could not get current billing info: {e}")
        
        # Set the billing account to empty to detach billing
        billing_info = {'billingAccountName': ''}  # Empty string means "disable billing"
        
        print(f"Executing API request to detach billing from project {project_id}")
        logger.info(f"Executing API request to detach billing from project {project_id}")
        
        # Execute the request to detach billing
        result = service.projects().updateBillingInfo(name=name, body=billing_info).execute()
        
        print(f"Successfully detached billing from project {project_id}")
        logger.info(f"Successfully detached billing from project {project_id}")
        
        return {"success": True, "message": f"Successfully detached billing from project {project_id}"}
    except Exception as e:
        error_msg = f"Error detaching billing: {e}"
        print(error_msg)
        logger.error(error_msg, exc_info=True)
        
        # As a fallback, try the gcloud command
        try:
            print("Attempting fallback method using Google Cloud SDK...")
            logger.info("Attempting fallback method using Google Cloud SDK...")
            
            import subprocess
            command = ["gcloud", "billing", "projects", "unlink", project_id]
            process = subprocess.run(command, capture_output=True, text=True, check=True)
            
            print(f"Successfully detached billing using fallback method: {process.stdout}")
            logger.info(f"Successfully detached billing using fallback method: {process.stdout}")
            
            return {"success": True, "message": f"Successfully detached billing from project {project_id} using fallback method"}
        except Exception as fallback_error:
            error_msg = f"Fallback method also failed: {fallback_error}"
            print(error_msg)
            logger.error(error_msg, exc_info=True)
            raise Exception(f"All attempts to detach billing failed: {e}. Fallback error: {fallback_error}")
        
        raise