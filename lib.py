import hashlib
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
    filename = hashlib.sha1(BASE_URL.encode('utf-8')).hexdigest() + '_session_id.key'
    f = open(filename, 'r')
    token = f.read()
    f.close()
    return token

def fetch_lua_algo(name):
    filename = './app/' + name
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
