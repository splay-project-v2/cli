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

@main.command()
@click.argument('username', nargs=1)
@click.argument('email', nargs=1)
@click.argument('password', nargs=1)
@click.argument('password_conf', nargs=1)
def new_user(username, email, password, password_conf):
    """Creates user with <username>, <email>, <password> and <password_conf>"""
    endpoint = BASE_URL + 'users'
    headers = authentified_headers()
    data = request_body('user', {
        'username': username, 'password': password, 'email': email, 'password_confirmation': password_conf
    })
    response = requests.post(endpoint, headers=headers, data=data)
    click.echo(response.json())

@main.command()
@click.argument('user_id', nargs=1)
def remove_user(user_id):
    """Removes user referred by <user_id>, admin only."""
    endpoint = BASE_URL + 'users/' + user_id
    headers = authentified_headers()
    response = requests.delete(endpoint, headers=headers)
    click.echo(response.json())

@main.command()
def list_splayds():
    """List Splay Daemons, called Splayds"""
    endpoint = BASE_URL + 'splayds'
    headers = authentified_headers()
    response = requests.get(endpoint, headers=headers)
    click.echo(response.json())
####################
## Main procedure ##
####################

if __name__ == "__main__":
    main()

######################
## Shitty functions ##
######################
