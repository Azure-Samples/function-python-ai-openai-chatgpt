import json
import logging
import azure.functions as func
import os
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from datetime import datetime

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

from openai import AzureOpenAI

# Configuration for Azure OpenAI (using Responses API)
endpoint = os.getenv("AZURE_OPENAI_ENDPOINT")
model_name = os.getenv("MODEL_DEPLOYMENT_NAME")
token_provider = get_bearer_token_provider(DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default")
api_version = "2025-03-01-preview"  # Required for Responses API

client = AzureOpenAI(
    api_version=api_version,
    azure_endpoint=endpoint,
    azure_ad_token_provider=token_provider,
)

# Table name for chat sessions
table_name = "ChatSessions"


# Simple ask http POST function that returns the completion based on prompt
# This OpenAI completion input requires a {prompt} value in json POST body
@app.function_name("ask")
@app.route(route="ask", methods=["POST"])
def ask(req: func.HttpRequest) -> func.HttpResponse:
    try:
        req_body = req.get_json()
        prompt = req_body.get('prompt')

        if not prompt:
            return func.HttpResponse("Please provide 'prompt' in the request body.", status_code=400)

        logging.info(f"Processing POST request. Prompt: {prompt}")

        response = client.chat.completions.create(
            model=model_name,
            messages=[{"role": "user", "content": prompt}]
        )
        return func.HttpResponse(response.choices[0].message.content, status_code=200)

    except (ValueError, TypeError):
        return func.HttpResponse("Invalid JSON in request body", status_code=400)
    except Exception as e:
        logging.error(f"Error processing request: {e}")
        return func.HttpResponse("Internal server error", status_code=500)


# Simple WhoIs http GET function that returns the completion based on name
@app.function_name("whois")
@app.route(route="whois/{name}", methods=["GET"])
def whois(req: func.HttpRequest) -> func.HttpResponse:
    try:
        name = req.route_params.get('name')
        
        if not name:
            return func.HttpResponse("Please provide a name in the URL path.", status_code=400)

        logging.info(f"Processing GET request for name: {name}")

        response = client.chat.completions.create(
            model=model_name,
            messages=[{"role": "user", "content": f"Who is {name}?"}],
            max_tokens=100
        )
        return func.HttpResponse(response.choices[0].message.content, status_code=200)

    except Exception as e:
        logging.error(f"Error processing whois request: {e}")
        return func.HttpResponse("Internal server error", status_code=500)


# Create or get existing chat session
@app.function_name("CreateChatBot")
@app.route(route="chats/{chatId}", methods=["PUT"])
@app.table_output(arg_name="chat_table", table_name=table_name, connection="AzureWebJobsStorage")
def create_chat_bot(req: func.HttpRequest, chat_table: func.Out[str]) -> func.HttpResponse:
    try:
        chat_id = req.route_params.get("chatId")
        input_json = req.get_json()
        instructions = input_json.get("instructions", "You are a helpful assistant.") if input_json else "You are a helpful assistant."
        
        # Create/update chat entity (upsert)
        entity = {
            "PartitionKey": "chat",
            "RowKey": chat_id,
            "instructions": instructions,
            "previous_response_id": "",
            "created_at": datetime.utcnow().isoformat(),
            "ETag": "*"
        }
        
        chat_table.set(json.dumps(entity))
        return func.HttpResponse(json.dumps({"chatId": chat_id}), status_code=201,
                                mimetype="application/json")
    
    except Exception as e:
        logging.error(f"Error creating chat: {e}")
        return func.HttpResponse("Internal server error", status_code=500)


# Get chat session info
@app.function_name("GetChatState")
@app.route(route="chats/{chatId}", methods=["GET"])
@app.table_input(arg_name="chat_entity", table_name=table_name, 
                 partition_key="chat", row_key="{chatId}", connection="AzureWebJobsStorage")
def get_chat_state(req: func.HttpRequest, chat_entity: str) -> func.HttpResponse:
    try:
        chat_id = req.route_params.get("chatId")
        
        if not chat_entity:
            return func.HttpResponse("Chat not found", status_code=404)
        
        # Find the specific entity in the response
        entities = json.loads(chat_entity) if isinstance(chat_entity, str) else chat_entity
        if isinstance(entities, list):
            entity = next((e for e in entities if e.get("RowKey") == chat_id), None)
        else:
            entity = entities
        
        if not entity:
            return func.HttpResponse("Chat not found", status_code=404)
            
        return func.HttpResponse(json.dumps({
            "instructions": entity.get("instructions", ""),
            "previous_response_id": entity.get("previous_response_id", ""),
            "created_at": entity.get("created_at", "")
        }), status_code=200, mimetype="application/json")
    
    except Exception as e:
        logging.error(f"Error getting chat state: {e}")
        return func.HttpResponse("Internal server error", status_code=500)


# Send message to chat and get AI response
@app.function_name("PostUserResponse")
@app.route(route="chats/{chatId}", methods=["POST"])
@app.table_input(arg_name="chat_entity", table_name=table_name, 
                 partition_key="chat", row_key="{chatId}", connection="AzureWebJobsStorage")
@app.table_output(arg_name="chat_table", table_name=table_name, connection="AzureWebJobsStorage")
def post_user_response(req: func.HttpRequest, chat_entity: str, chat_table: func.Out[str]) -> func.HttpResponse:
    try:
        chat_id = req.route_params.get("chatId")
        req_body = req.get_json()
        message = req_body.get('message') if req_body else None
        
        if not message:
            return func.HttpResponse("Message is required", status_code=400)
        if not chat_entity:
            return func.HttpResponse("Chat not found", status_code=404)
        
        # Find the specific entity in the response
        entities = json.loads(chat_entity) if isinstance(chat_entity, str) else chat_entity
        if isinstance(entities, list):
            entity = next((e for e in entities if e.get("RowKey") == chat_id), None)
        else:
            entity = entities
        
        if not entity:
            return func.HttpResponse("Chat not found", status_code=404)
        
        # Prepare Azure OpenAI request
        params = {
            "model": model_name,
            "input": [{"role": "user", "content": message}]
        }
        
        if entity.get("instructions"):
            params["instructions"] = entity["instructions"]
        if entity.get("previous_response_id"):
            params["previous_response_id"] = entity["previous_response_id"]
        
        # Get AI response
        response = client.responses.create(**params)
        
        # Update chat state
        updated_entity = {
            "PartitionKey": "chat",
            "RowKey": chat_id,
            "instructions": entity.get("instructions", "You are a helpful assistant."),
            "previous_response_id": response.id,
            "created_at": entity.get("created_at", datetime.utcnow().isoformat()),
            "ETag": "*"
        }
        
        chat_table.set(json.dumps(updated_entity))
        return func.HttpResponse(response.output_text, status_code=200, mimetype="text/plain")
    
    except Exception as e:
        logging.error(f"Error processing chat message: {e}")
        return func.HttpResponse("Internal server error", status_code=500)
