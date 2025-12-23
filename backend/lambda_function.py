import json
import boto3

# Initialize the DynamoDB client
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('xavieraws-stats') # We will create this table next

def lambda_handler(event, context):
    # This is a simple counter logic for your SAA-C03 project
    response = table.update_item(
        Key={'stat_name': 'view_count'},
        UpdateExpression='ADD visits :inc',
        ExpressionAttributeValues={':inc': 1},
        ReturnValues='UPDATED_NEW'
    )
    
    visit_count = response['Attributes']['visits']

    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*', # Required for your website to call this
            'Content-Type': 'application/json'
        },
        'body': json.dumps({'count': str(visit_count)})
    }