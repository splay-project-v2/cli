FROM python:3.7.2-slim
LABEL Description="Splay - RPC Client - App able to launch lua script to get/push information to the controller"

WORKDIR /app

COPY ./requirements.txt ./

RUN pip install -r requirements.txt

COPY . .

CMD tail -f /dev/null
