import json
import os
import boto3 # <-- Essential for interacting with AWS services like SES

# Define the email address you want to send form submissions to
# Set this as an environment variable in your template.yml later (best practice)
RECIPIENT_EMAIL = "zayjones3991@gmail.com" # <-- REPLACE THIS

# Initialize the SES client globally for reuse
# It will use the permissions granted by the Lambda Execution Role
ses_client = boto3.client('ses') 

def handler(event, context):
    """
    The main handler function for the AWS Lambda.
    Processes the incoming HTTP POST request from API Gateway.
    """
    print("--- New Contact Form Submission ---")
    
    # 1. CORS Preflight Check (If you get CORS errors, this is the fix)
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': ''
        }
        
    # 2. Parse the incoming request body
    try:
        # Load the JSON string from the 'body' attribute
        request_body = json.loads(event.get('body', '{}'))
        
        name = request_body.get('name', 'N/A')
        email = request_body.get('email', 'N/A')
        message = request_body.get('message', 'No message provided')

        print(f"Data: Name={name}, Email={email}")

    except Exception as e:
        print(f"ERROR: Failed to parse request body: {e}")
        return create_response(500, 'Invalid request format.')

    # 3. Email Sending Logic using Amazon SES
    try:
        # Construct the email body
        email_body = f"Name: {name}\nEmail: {email}\n\nMessage:\n{message}"
        
        # Send the email via SES
        ses_client.send_email(
            Source=RECIPIENT_EMAIL, # Must be a verified email/domain in SES
            Destination={'ToAddresses': [RECIPIENT_EMAIL]},
            Message={
                'Subject': {'Data': f"New Contact from {name} ({email})"},
                'Body': {'Text': {'Data': email_body}}
            }
        )
        
        print("Email sent successfully via SES.")
        
    except Exception as e:
        print(f"ERROR: SES Email failed: {e}")
        # The frontend still gets a 200 if the form was valid, 
        # but we log the failure internally. Or you can return a 500 here.
        return create_response(500, 'Could not send email. Check logs.')

    # 4. Return a successful 200 response
    return create_response(200, 'Form submission received and processed.')


def create_response(status_code, message):
    """Helper function to create a standardized API Gateway response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Access-Control-Allow-Origin': '*', # Important for CORS
            'Content-Type': 'application/json'
        },
        'body': json.dumps({'message': message})
    }
