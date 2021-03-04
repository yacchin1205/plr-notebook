import asyncio
import logging
from plrfs.rpc_client import PLRFSClient

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

async def traverseFiles(client, path, indent=''):
    files = await client.get_files(path)
    for f in files:
        print('{}- {}'.format(indent, f))
        if f['kind'] == 'file':
            content = await client.get_file(path + [f['id']])
            print('{}  => {}'.format(indent, content))
        if f['kind'] != 'folder':
            continue
        await traverseFiles(client, path + [f['id']], indent=indent + '  ')

async def main(loop):
    client = await PLRFSClient(loop).connect()
    await traverseFiles(client, [])

loop = asyncio.get_event_loop()
loop.run_until_complete(main(loop))
