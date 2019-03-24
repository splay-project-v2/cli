#!/usr/bin/env python3
from lib import *

__author__ = "Samuel Monroe & Rémy Voet"

@click.group()
def main():
    """
    Simple Splay CLI for querying the Backend Service
    """
    pass

@main.command()
@click.argument('username', nargs=1)
@click.argument('password', nargs=1)
def start_session(username, password):
    """Init a session by providing <username> and <password>"""
    endpoint = BASE_URL + 'sessions'
    data = request_body('session', {'username': username, 'password': password})
    response = requests.post(endpoint, data=json.dumps(data))
    check_response(response)
    store_session(response.json()['token'])

@main.command()
def list_users():
    """List Splay Users, must be admin and started a session."""
    endpoint = BASE_URL + 'users'
    headers = authentified_headers()
    response = requests.get(endpoint, headers=headers)
    check_response(response)
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
    response = requests.post(endpoint, headers=headers, data=json.dumps(data))
    check_response(response)
    click.echo(response.json())

@main.command()
@click.argument('user_id', nargs=1)
def remove_user(user_id):
    """Removes user referred by <user_id>, admin only."""
    endpoint = BASE_URL + 'users/' + user_id
    headers = authentified_headers()
    response = requests.delete(endpoint, headers=headers)
    check_response(response)
    click.echo(response.json())

@main.command()
def list_splayds():
    """List Splay Daemons, called Splayds"""
    endpoint = BASE_URL + 'splayds'
    headers = authentified_headers()
    response = requests.get(endpoint, headers=headers)
    check_response(response)
    for item in response.json()['splayds']:
        click.echo("* [Splayd id : " + str(item['id']) + "]")
        click.echo("\t # IP     " + item['ip'])
        click.echo("\t # Status " + item['status'])
        click.echo("\t # Key    " + item['key'])

@main.command()
def list_jobs():
    """List Splay Jobs"""
    endpoint = BASE_URL + 'jobs'
    headers = authentified_headers()
    response = requests.get(endpoint, headers=headers)
    check_response(response)
    click.echo(response.json())

@main.command()
@click.argument('job_id', nargs=1)
def kill_job(job_id):
    """Kill Splay Job referred by <job_id>"""
    endpoint = BASE_URL + 'jobs/' + job_id
    headers = authentified_headers()
    response = requests.delete(endpoint, headers=headers)
    check_response(response)
    click.echo(response.json())

@main.command()
@click.argument('job_id', nargs=1)
def get_job_code(job_id):
    """Get Splay Job Code referred by <job_id>"""
    endpoint = BASE_URL + 'jobs/' + job_id
    headers = authentified_headers()
    response = requests.get(endpoint, headers=headers)
    check_response(response)
    click.echo(response.json()['job']['code'])

@main.command()
@click.argument('job_id', nargs=1)
def get_job_details(job_id):
    """Get Splay Job details referred by <job_id>"""
    endpoint = BASE_URL + 'jobs/' + job_id
    headers = authentified_headers()
    response = requests.get(endpoint, headers=headers)
    check_response(response)
    click.echo(response.json()['job'])

@main.command()
@click.option('--name', '-n', help='Name of the job.')
@click.option('--description', '-d',  help='Description of the job.')
@click.option('--nb_splayds', '-s',  default=1, help='Number of splayds.')
@click.argument('filename', nargs=1)
def submit_job(name, description, nb_splayds, filename):
    """Submit new job, specifying a name of lua code file and optional args."""
    endpoint = BASE_URL + 'jobs'
    headers = authentified_headers()
    data = request_body('user', { 'code': fetch_lua_algo(filename) })
    if name:
        data['data']['attributes']['name'] = name
    if description:
        data['data']['attributes']['description'] = description
    if nb_splayds:
        data['data']['attributes']['nb_splayds'] = nb_splayds
    response = requests.post(endpoint, headers=headers, data=json.dumps(data))
    check_response(response)
    click.echo("Job submitted")
    click.echo("Job ID        : " + response.json()['job']['id'])
    click.echo("Job reference : " + response.json()['job']['ref'])

if __name__ == "__main__":
    main()
