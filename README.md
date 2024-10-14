---
page_type: sample
languages:
- azdeveloper
- python
- bicep
- html
products:
- azure
- azure-functions
- azure-pipelines
- azure-openai
- azure-cognitive-search
- ai-services
- blob-storage
- table-storage
urlFragment: function-python-ai-openai-chatgpt
name: Azure Functions - Chat using ChatGPT (Python Function)
description: This sample shows simple ways to interact with ChatGPT & OpenAI using Azure Functions [Open AI Triggers and Bindings extension](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-openai?tabs=isolated-process&pivots=programming-language-javascript).  You can issue simple prompts and receive completions using the `ask` function, and you can send messages and perform a stateful session with a friendly ChatBot using the `chat` function.
---
<!-- YAML front-matter schema: https://review.learn.microsoft.com/en-us/help/contribute/samples/process/onboarding?branch=main#supported-metadata-fields-for-readmemd -->

# Azure Functions
## Chat using ChatGPT (Python v2 Function)

This sample shows simple ways to interact with ChatGPT & OpenAI using Azure Functions [Open AI Triggers and Bindings extension](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-openai?tabs=isolated-process&pivots=programming-language-javascript).  You can issue simple prompts and receive completions using the `ask` function, and you can send messages and perform a stateful session with a friendly ChatBot using the `chats` function.  The app deploys easily to Azure Functions Flex Consumption hosting plan using `azd up`. 

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/Azure-Samples/function-python-ai-openai-chatgpt)

## Run on your local environment

### Pre-reqs
1) [Python 3.8+](https://www.python.org/) 
2) [Azure Functions Core Tools 4.0.6280 or higher](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local?tabs=v4%2Cmacos%2Ccsharp%2Cportal%2Cbash#install-the-azure-functions-core-tools)
3) [Azurite](https://github.com/Azure/Azurite)

The easiest way to install Azurite is using a Docker container or the support built into Visual Studio:
```bash
docker run -d -p 10000:10000 -p 10001:10001 -p 10002:10002 mcr.microsoft.com/azure-storage/azurite
```

4) Once you have your Azure subscription, run the following in a new terminal window to create all the AI Language and other resources needed:
```azd provision```

Take note of the value of `AZURE_OPENAI_ENDPOINT` which can be found in `./.azure/<env name from azd provision>/.env`.  It will look something like:
```bash
AZURE_OPENAI_ENDPOINT="https://cog-<unique string>.openai.azure.com/"
```

Alternatively you can [create an OpenAI resource](https://portal.azure.com/#create/Microsoft.CognitiveServicesTextAnalytics) in the Azure portal to get your key and endpoint. After it deploys, click Go to resource and view the Endpoint value.  You will also need to deploy a model, e.g. with name `chat` and model `gpt-35-turbo`.

5) Add this `local.settings.json` file to the root of the repo folder to simplify local development.  Replace `AZURE_OPENAI_ENDPOINT` with your value from step 4.  Optionally you can choose a different model deployment in `CHAT_MODEL_DEPLOYMENT_NAME`.  This file will be gitignored to protect secrets from committing to your repo, however by default the sample uses Entra identity (user identity and mananaged identity) so it is secretless.  
```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "UseDevelopmentStorage=true",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AZURE_OPENAI_ENDPOINT": "https://cog-<unique string>.openai.azure.com/",
    "CHAT_MODEL_DEPLOYMENT_NAME": "chat",
    "AzureWebJobsFeatureFlags": "EnableWorkerIndexing",
    "PYTHON_ISOLATE_WORKER_DEPENDENCIES": "1"
  }
}
```

## Simple Prompting with Ask Function
### Using Functions CLI
1) Open a new terminal and do the following:

```bash
pip3 install -r requirements.txt
func start
```
2) Using your favorite REST client, e.g. [RestClient in VS Code](https://marketplace.visualstudio.com/items?itemName=humao.rest-client), PostMan, curl, make a post.  [test.http](test.http) has been provided to run this quickly.   

Terminal:
```bash
curl -i -X POST http://localhost:7071/api/ask/ \
  -H "Content-Type: text/json" \
  --data-binary "@testdata.json"
```

testdata.json
```json
{
    "prompt": "Write a poem about Azure Functions.  Include two reasons why users love them."
}
```

[test.http](test.http)
```http
### Simple Ask Completion
POST http://localhost:7071/api/ask HTTP/1.1
content-type: application/json

{
    "prompt": "Tell me two most popular programming features of Azure Functions"
}

### Simple Whois Completion
GET http://localhost:7071/api/whois/Turing HTTP/1.1
```

## Stateful Interaction with Chatbot using Chat Function

We will use the [test.http](test.http) file again now focusing on the Chat function.  We need to start the chat with `chats` and send messages with `PostChat`.  We can also get state at any time with `GetChatState`.

```http
### Stateful Chatbot
### CreateChatBot
PUT http://localhost:7071/api/chats/abc123
Content-Type: application/json

{
    "name": "Sample ChatBot",
    "description": "This is a sample chatbot."
}

### PostChat
POST http://localhost:7071/api/chats/abc123
Content-Type: application/json

{
    "message": "Hello, how can I assist you today?"
}

### PostChat
POST http://localhost:7071/api/chats/abc123
Content-Type: application/json

{
    "message": "Need help with directions from Redmond to SeaTac?"
}

### GetChatState
GET http://localhost:7071/api/chats/abc123?timestampUTC=2024-01-15T22:00:00
Content-Type: application/json
```

## Deploy to Azure

The easiest way to deploy this app is using the [Azure Developer CLI](https://aka.ms/azd).  If you open this repo in GitHub CodeSpaces the AZD tooling is already preinstalled.

To provision and deploy:
```bash
azd up
```

## Source Code

The key code that makes the prompting and completion work is as follows in [function_app.py](function_app.py).  The `/api/ask` function and route expects a prompt to come in the POST body.  The templating pattern is used to define the input binding for prompt and the underlying parameters for OpenAI models like the maxTokens and the AI model to use for chat.  

The whois function expects a name to be sent in the route `/api/whois/<name>` and you get to see a different example of a route and parameter coming in via http GET.  

### Simple prompting and completions with ChatGPT

```python
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
```

### Stateful ChatBots with ChatGPT

The stateful chatbot is shown in [function_app.py](function_app.py) routing to `/api/chats`.  This is a stateful function meaning you can create or ask for a session by <chatId> and continue where you left off with the same context and memories stored by the function binding (backed Table storage).  This makes use of the Assistants feature of the Azure Functions OpenAI extension that has a set of inputs and outputs for this case.  

To create or look up a session we have the CreateChatBot as an http PUT function.  Note how the code will reuse your AzureWebJobStorage connection.  The output binding of `assistantCreate` will actually kick off the create.  

```python
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
```

Subsequent chat messages are sent to the chat as http POST, being careful to use the same chatId.  This makes use of the `inputAssistant` input binding to take message as input and do the completion, while also automatically pulling context and memories for the session, and also saving your new state.
```python
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
```

The [test.http](test.http) file is helpful to see how clients and APIs should call these functions, and to learn the typical flow.  

You can customize this or learn more using [Open AI Triggers and Bindings extension](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-openai?tabs=isolated-process&pivots=programming-language-javascript).  
