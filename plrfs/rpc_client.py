import json
import uuid
from base64 import b64decode
import zmq

class PLRFSClient:

    def __init__(self, loop):
        self.context = None
        self.socket = None
        self.loop = loop

    async def connect(self, host='tcp://localhost:5555'):
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REQ)
        self.socket.connect(host)
        return self

    async def get_files(self, path):
        return await self._call({
            'name': 'get-files',
            'path': path,
        })

    async def get_file(self, path):
        f = await self._call({
            'name': 'get-file',
            'path': path,
        })
        f['content'] = b64decode(f['content'])
        return f

    async def _call(self, request):
        self.socket.send(json.dumps(request).encode('utf8'))
        response = json.loads(self.socket.recv().decode('utf8'))
        if response['success']:
            return response['result']
        raise Exception('error: {}'.format(response['error']))
