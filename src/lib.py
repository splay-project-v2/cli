import hashlib
import click
import requests
import json
import sys
from config import *

def request_body(type, attributes):
    return { 'data': {
                'type': type,
                'attributes': attributes
             }
           }

def store_session(token):
    filename = hashlib.sha1(BASE_URL.encode('utf-8')).hexdigest() + '_session_id.key'
    f = open(filename, 'w')
    f.write(token)
    f.close()

def fetch_session():
    try:
      filename = hashlib.sha1(BASE_URL.encode('utf-8')).hexdigest() + '_session_id.key'
      f = open(filename, 'r')
      token = f.read()
      f.close()
      return token
    except IOError:
      print("Not token could be retrieved.")
      print("Please start a session using 'start-session' command.")
      sys.exit()

def fetch_lua_algo(name):
    filename = '../algorithms/' + name
    f = open(filename, 'r')
    code = f.read()
    f.close()
    return code

def authentified_headers():
    token = fetch_session()
    return {
        'AUTHORIZATION': 'Bearer ' + token,
        'CONTENT_TYPE': 'application/vnd.splay+json; version=1'
    }

def check_response(response):
    if response.status_code != 200:
        click.echo("Error code : " + str(response.status_code))
        click.echo("Message : " + response.json()['errors'])
        click.echo("Contact administrator or review command usage with --help option")
        sys.exit()
