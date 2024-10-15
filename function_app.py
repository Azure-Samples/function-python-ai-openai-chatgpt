import json
import logging
import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)


# Simple ask http POST function that returns the completion based on prompt
# This OpenAI completion input requires a {prompt} value in json POST body
@app.function_name("ask")
@app.route(route="ask", methods=["POST"])
@app.text_completion_input(arg_name="response", prompt="{prompt}",
                           model="%CHAT_MODEL_DEPLOYMENT_NAME%")
def ask(req: func.HttpRequest, response: str) -> func.HttpResponse:
    response_json = json.loads(response)
    return func.HttpResponse(response_json["content"], status_code=200)


# Simple WhoIs http GET function that returns the completion based on name
# This OpenAI completion input requires a {name} binding value.
@app.function_name("whois")
@app.route(route="whois/{name}", methods=["GET"])
@app.text_completion_input(arg_name="response", prompt="Who is {name}?",
                           max_tokens="100",
                           model="%CHAT_MODEL_DEPLOYMENT_NAME%")
def whois(req: func.HttpRequest, response: str) -> func.HttpResponse:
    response_json = json.loads(response)
    return func.HttpResponse(response_json["content"], status_code=200)


CHAT_STORAGE_CONNECTION = "AzureWebJobsStorage"
COLLECTION_NAME = "ChatState"


# http PUT function to start ChatBot conversation based on a chatID
@app.function_name("CreateChatBot")
@app.route(route="chats/{chatId}", methods=["PUT"])
@app.assistant_create_output(arg_name="requests")
def create_chat_bot(req: func.HttpRequest,
                    requests: func.Out[str]) -> func.HttpResponse:
    chatId = req.route_params.get("chatId")
    input_json = req.get_json()
    logging.info(
        f"Creating chat ${chatId} from input parameters " +
        "${json.dumps(input_json)}")
    create_request = {
        "id": chatId,
        "instructions": input_json.get("instructions"),
        "chatStorageConnectionSetting": CHAT_STORAGE_CONNECTION,
        "collectionName": COLLECTION_NAME
    }
    requests.set(json.dumps(create_request))
    response_json = {"chatId": chatId}
    return func.HttpResponse(json.dumps(response_json), status_code=202,
                             mimetype="application/json")


# http GET function to get ChatBot conversation with chatID & timestamp
@app.function_name("GetChatState")
@app.route(route="chats/{chatId}", methods=["GET"])
@app.assistant_query_input(
    arg_name="state",
    id="{chatId}",
    timestamp_utc="{Query.timestampUTC}",
    chat_storage_connection_setting=CHAT_STORAGE_CONNECTION,
    collection_name=COLLECTION_NAME
)
def get_chat_state(req: func.HttpRequest, state: str) -> func.HttpResponse:
    return func.HttpResponse(state, status_code=200,
                             mimetype="application/json")


# http POST function for user to send a message to ChatBot with chatID
@app.function_name("PostUserResponse")
@app.route(route="chats/{chatId}", methods=["POST"])
@app.assistant_post_input(
    arg_name="state", id="{chatId}",
    user_message="{message}",
    model="%CHAT_MODEL_DEPLOYMENT_NAME%",
    chat_storage_connection_setting=CHAT_STORAGE_CONNECTION,
    collection_name=COLLECTION_NAME
    )
def post_user_response(req: func.HttpRequest, state: str) -> func.HttpResponse:
    # Parse the JSON string into a dictionary
    data = json.loads(state)

    # Extract the content of the recentMessage
    recent_message_content = data['recentMessages'][0]['content']
    return func.HttpResponse(recent_message_content, status_code=200,
                             mimetype="text/plain")
