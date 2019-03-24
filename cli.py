#!/usr/bin/env python3

import click
import requests
import json
import hashlib

__author__ = "Samuel Monroe & Rémy Voet"

BASE_URL = "http://localhost:8081/api/v1/"

def request_body(type, attributes):
    return json.dumps({
            'data': {
                'type': type,
                'attributes': attributes
            }
        })

def store_session(token):
    filename = hashlib.sha1(BASE_URL.encode('utf-8')).hexdigest() + '_session_id.key'
    f = open(filename, 'w')
    f.write(token)
    f.close

def fetch_session():
    filename = hashlib.sha1(BASE_URL.encode('utf-8')).hexdigest() + '_session_id.key'
    f = open(filename, 'r')
    return f.read()
    f.close

def authentified_headers():
    token = fetch_session()
    return {
        'AUTHORIZATION': 'Bearer ' + token,
        'CONTENT_TYPE': 'application/vnd.splay+json; version=1'
    }

@click.group()
def main():
    """
    Simple Splay CLI for querying the Backend Service
    """
    pass


##############
## Commands ##
##############

@main.command()
@click.argument('username', nargs=1)
@click.argument('password', nargs=1)
def start_session(username, password):
    """Init a session by providing <username> and <password>"""
    endpoint = BASE_URL + 'sessions'
    data = request_body('session', {'username': username, 'password': password})
    response = requests.post(endpoint, data=data)
    store_session(response.json()['token'])

@main.command()
def list_users():
    """List Splay Users, must be admin and started a session."""
    endpoint = BASE_URL + 'users'
    headers = authentified_headers()
    response = requests.get(endpoint, headers=headers)
    click.echo(response.json()['users'])
####################
## Main procedure ##
####################

if __name__ == "__main__":
    main()

######################
## Shitty functions ##
######################
