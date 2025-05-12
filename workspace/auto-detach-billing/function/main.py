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
    # Log the received event
    logger.info("FUNCTION STARTED: detach_billing function triggered")
    
    try:
        # Extract the Pub/Sub message data
        if not hasattr(cloud_event, 'data') or not cloud_event.data:
            logger.warning("Cloud event contains no data")
            return

        # The Pub/Sub message is contained in the data field of the CloudEvent
        pub_sub_message = cloud_event.data.get('message', {})
        logger.info(f"Pub/Sub message: {pub_sub_message}")
        
        # The message data is base64-encoded
        if 'data' not in pub_sub_message:
            logger.warning("No data field in Pub/Sub message")
            return
            
        message_data = base64.b64decode(pub_sub_message['data']).decode('utf-8')
        logger.info(f"Decoded message: {message_data}")
        
        # Parse the JSON payload, being careful about format
        try:
            # Try to parse as valid JSON
            budget_notification = json.loads(message_data)
            logger.info(f"Budget notification: {budget_notification}")
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse message as JSON: {e}")
            
            # Fallback: just try to extract projectId if it appears in the message
            if "projectId" in message_data:
                match = re.search(r'projectId["\s:=]+([^,"}\s]+)', message_data)
                if match:
                    project_id = match.group(1)
                    logger.info(f"Extracted project ID using regex: {project_id}")
                    
                    # Create a simplified budget notification
                    budget_notification = {
                        "costAmount": 9999, # High value to ensure condition is met
                        "budgetAmount": 100,
                        "projectId": project_id
                    }
                else:
                    logger.error("Could not extract project ID from malformed message")
                    return
            else:
                logger.error("No project ID found in message")
                return
            
        # Process the budget notification
        process_budget_notification(budget_notification)
            
    except Exception as e:
        logger.error(f"Error processing cloud event: {e}", exc_info=True)
        raise

def process_budget_notification(budget_notification):
    """Process the budget notification and detach billing if conditions are met."""
    logger.info("FUNCTION: process_budget_notification started")
    
    try:
        # Extract relevant data from the budget notification
        cost_amount = budget_notification.get('costAmount')
        budget_amount = budget_notification.get('budgetAmount')
        logger.info(f"Cost amount: {cost_amount}, Budget amount: {budget_amount}")
        
        # Either use alertThresholdExceeded or calculate from the amounts
        alert_threshold_exceeded = budget_notification.get('alertThresholdExceeded')
        if alert_threshold_exceeded is None and cost_amount and budget_amount:
            alert_threshold_exceeded = cost_amount / budget_amount
        logger.info(f"Alert threshold exceeded: {alert_threshold_exceeded}")
            
        # Extract project ID
        project_id = budget_notification.get('projectId')
        if not project_id:
            logger.error("Could not determine project ID from notification")
            return
            
        logger.info(f"Processing budget alert for project {project_id}")
        
        # Define your conditions for detaching billing
        should_detach = evaluate_detach_conditions(
            cost_amount, 
            budget_amount, 
            alert_threshold_exceeded,
            project_id
        )
        
        logger.info(f"Should detach billing: {should_detach}")
        
        if should_detach:
            result = detach_billing_account(project_id)
            logger.info(f"Billing detachment result: {result}")
        else:
            logger.info(f"Conditions not met for detaching billing from project {project_id}")
            
    except Exception as e:
        logger.error(f"Error processing budget notification: {e}", exc_info=True)
        raise

def evaluate_detach_conditions(cost_amount, budget_amount, alert_threshold_exceeded, project_id):
    """
    Evaluate whether billing should be detached based on your specific conditions.
    """
    logger.info("FUNCTION: evaluate_detach_conditions started")
    
    # Get exclusion list from environment variable
    exclusion_list = [p.strip() for p in os.environ.get('EXCLUSION_LIST', '').split(',') if p.strip()]
    logger.info(f"Exclusion list: {exclusion_list}")
    
    # Get allowed overage percentage from environment variable (default to 10%)
    allowed_overage_pct = float(os.environ.get('ALLOWED_OVERAGE_PCT', '10'))
    max_threshold = 1.0 + (allowed_overage_pct / 100)
    logger.info(f"Allowed overage percentage: {allowed_overage_pct}%, Max threshold: {max_threshold}")
    
    # Check conditions
    is_exceeding_threshold = alert_threshold_exceeded >= max_threshold
    is_in_exclusion_list = project_id in exclusion_list
    
    logger.info(f"Is exceeding threshold: {is_exceeding_threshold}, Is in exclusion list: {is_in_exclusion_list}")
    
    # Example condition: Detach if threshold exceeded by more than allowed overage and not in exclusion list
    if (is_exceeding_threshold and not is_in_exclusion_list):
        logger.info(f"Condition met: Threshold {alert_threshold_exceeded} exceeds max allowed {max_threshold}")
        return True
    
    if not is_exceeding_threshold:
        logger.info(f"Condition not met: Threshold {alert_threshold_exceeded} does not exceed max allowed {max_threshold}")
    
    if is_in_exclusion_list:
        logger.info(f"Condition not met: Project {project_id} is in exclusion list")
    
    return False

def detach_billing_account(project_id):
    """
    Detach billing account from the specified project.
    This implementation actually detaches the billing account.
    """
    logger.info("FUNCTION: detach_billing_account started - WILL ACTUALLY DETACH BILLING")
    
    try:
        # Use the Cloud Billing API to detach billing
        service = discovery.build('cloudbilling', 'v1', cache_discovery=False)
        
        # Format the project name
        name = f'projects/{project_id}'
        
        logger.info(f"Getting current billing info for project {project_id}")
        
        try:
            # Get current billing info to log it
            billing_info = service.projects().getBillingInfo(name=name).execute()
            current_billing_account = billing_info.get('billingAccountName', 'Not found')
            logger.info(f"Current billing account for project {project_id}: {current_billing_account}")
        except Exception as e:
            logger.warning(f"Could not get current billing info: {e}")
        
        # Set the billing account to empty to detach billing
        billing_info = {'billingAccountName': ''}  # Empty string means "disable billing"
        
        logger.info(f"Executing API request to detach billing from project {project_id}")
        
        # Execute the request to detach billing
        result = service.projects().updateBillingInfo(name=name, body=billing_info).execute()
        
        logger.info(f"Successfully detached billing from project {project_id}")
        
        return {"success": True, "message": f"Successfully detached billing from project {project_id}"}
    except Exception as e:
        logger.error(f"Error detaching billing: {e}", exc_info=True)
        
        # As a fallback, try the gcloud command
        try:
            logger.info("Attempting fallback method using Google Cloud SDK...")
            
            import subprocess
            command = ["gcloud", "billing", "projects", "unlink", project_id]
            process = subprocess.run(command, capture_output=True, text=True, check=True)
            
            logger.info(f"Successfully detached billing using fallback method: {process.stdout}")
            
            return {"success": True, "message": f"Successfully detached billing from project {project_id} using fallback method"}
        except Exception as fallback_error:
            logger.error(f"Fallback method also failed: {fallback_error}", exc_info=True)
            raise Exception(f"All attempts to detach billing failed: {e}. Fallback error: {fallback_error}")
        
        raise