---
page_type: sample
languages:
- azdeveloper
- python
- bicep
products:
- azure
- azure-functions
- azure-openai
urlFragment: function-python-ai-openai-chatgpt
name: Azure Functions - Chat using ChatGPT (Python v2 Function)
description: Using ChatGPT prompt with Python as HTTP Get or Post input, calculates the completions using OpenAI ChatGPT service, returns the output plus caches.
---
<!-- YAML front-matter schema: https://review.learn.microsoft.com/en-us/help/contribute/samples/process/onboarding?branch=main#supported-metadata-fields-for-readmemd -->

# Azure Functions
## Chat using ChatGPT (Python v2 Function)

This sample shows how to take a ChatGPT prompt as HTTP Get or Post input, calculates the completions using OpenAI ChatGPT service, and then returns the output plus caches in a Blob state store.  

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=575770869)

## Run on your local environment

### Pre-reqs
1) [Python 3.8+](https://www.python.org/) 
2) [Azure Functions Core Tools](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local?tabs=v4%2Cmacos%2Ccsharp%2Cportal%2Cbash#install-the-azure-functions-core-tools)
3) [OpenAPI API key](https://platform.openai.com/account/api-keys) 
4) Export these secrets as Env Vars using values from Step 3.

Mac/Linux
```bash
export OPENAI_API_KEY=*Paste from step 3*
```

Windows

Search for Environment Variables in Settings, create new System Variables similarly to [these instructions](https://docs.oracle.com/en/database/oracle/machine-learning/oml4r/1.5.1/oread/creating-and-modifying-environment-variables-on-windows.html#GUID-DD6F9982-60D5-48F6-8270-A27EC53807D0):

| Variable | Value |
| -------- | ----- |
| OPENAI_API_KEY | *Paste from step 3* |

5) Add this local.settings.json file to the root folder to simplify local development and include Key from step 3
```json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AzureWebJobsFeatureFlags": "EnableWorkerIndexing",
    "AzureWebJobsStorage": "",
    "OPENAI_API_KEY": "*Paste from step 3*"
  }
}
```

### Using Functions CLI
1) Open a new terminal and do the following:

```bash
pip3 install -r requirements.text
func start
```
2) Using your favorite REST client, e.g. [RestClient in VS Code](https://marketplace.visualstudio.com/items?itemName=humao.rest-client), PostMan, curl, make a post.  `test.http` has been provided to run this quickly.   

Terminal:
```bash
curl -i -X POST http://localhost:7071/api/chat/ \
  -H "Content-Type: text/json" \
  --data-binary "@testdata.json"
```

testdata.json
```json
{
    "prompt": "Write a poem about Azure Functions.  Include two reasons why users love them."
}
```

test.http
```bash

POST http://localhost:7071/api/chat HTTP/1.1
content-type: application/json

{
    "prompt": "Write a poem about Azure Functions.  Include two reasons why users love them."
}
```

You will see chat happen in the Terminal standard out, the HTTP response, and saved off to a Blob for state management in the `samples-chatgpt-output` container.  

## Source Code

The key code that makes this work is as follows in `./function_app.py`.  You can customize this or learn more snippets using [Examples](https://platform.openai.com/examples) and [OpenAPI Playground](https://platform.openai.com/playground/).

```python
    completion = openai.Completion.create(
        model='text-davinci-003',
        prompt=generate_prompt(prompt),
        temperature=0.9,
        max_tokens=200
    )
    return completion.choices[0].text
```

## Deploy to Azure

The easiest way to deploy this app is using the [Azure Dev CLI aka AZD](https://aka.ms/azd).  If you open this repo in GitHub CodeSpaces the AZD tooling is already preinstalled.

To provision and deploy:
```bash
azd up
```
