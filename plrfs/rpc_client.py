import json
import uuid
from base64 import b64decode
from aio_pika import connect, IncomingMessage, Message

class PLRFSClient:

    def __init__(self, loop):
        self.connection = None
        self.channel = None
        self.callback_queue = None
        self.futures = {}
        self.loop = loop

    async def connect(self):
        self.connection = await connect(
            "amqp://guest:guest@localhost/", loop=self.loop
        )
        self.channel = await self.connection.channel()
        self.callback_queue = await self.channel.declare_queue(exclusive=True)
        await self.callback_queue.consume(self._on_response)

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

    async def _on_response(self, message: IncomingMessage):
        future = self.futures.pop(message.correlation_id)
        future.set_result(json.loads(message.body.decode('utf8')))

    async def _call(self, request):
        correlation_id = str(uuid.uuid4())
        future = self.loop.create_future()

        self.futures[correlation_id] = future

        await self.channel.default_exchange.publish(
            Message(
                json.dumps(request).encode('utf8'),
                content_type='text/plain',
                correlation_id=correlation_id,
                reply_to=self.callback_queue.name,
            ),
            routing_key="plrfsrpc",
        )
        response = await future
        if response['success']:
            return response['result']
        raise Exception('error: {}'.format(response['error']))
