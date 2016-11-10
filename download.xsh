#!/usr/bin/env xonsh

import sys
import json
import os
import tempfile

from Crypto.Cipher import AES
from Crypto.Util import Counter
from Crypto.Protocol.KDF import PBKDF2
from Crypto.Hash import SHA256

# check if symmetric cipher key is set in env
if not 'YTD_KEY' in ${...}:
	print('please set YTD_KEY according to the server:')
	sys.exit(1)

# read optional download speed rate limiting
ratelimit = []
if 'YTD_RATE' in ${...}:
	ratelimit = ['-r', $YTD_RATE]

# wrapper around a symmetric cipher
def getCipher():
	ctr = Counter.new(128)
	key = PBKDF2($YTD_KEY.encode('utf8'), salt=b'15AUt3q2X9CdEPAx', dkLen=32)
	return AES.new(key, mode=AES.MODE_CTR, counter=ctr)

# decrypt dlArchive file of youtube-dl to temporary file and return its filename
def decryptArchive():
	with tempfile.NamedTemporaryFile(delete=False) as tmpDlArchive:
		with open('dlArchive.txt.crypt', 'rb') as dlArchive:
			tmpDlArchive.write(getCipher().decrypt(dlArchive.read()))
	return tmpDlArchive.name

# encrypt dlArchive file of youtube-dl and overwrite previously existing crypted file, using the given file name as source
def encryptArchive(srcFileName):
	with open(srcFileName, 'r') as srcFile:
		with open('dlArchive.txt.crypt', 'wb') as dlArchive:
			dlArchive.write(getCipher().encrypt(srcFile.read()))

# update data files
git pull --no-rebase or true @(sys.exit(1))

# dlArchive file of youtube-dl
archiveFile = decryptArchive()

# read videolists from encrypted file
def readVideoLists():
	with open('listFile.json.crypt', 'rb') as listFileCryted:
		return json.loads(getCipher().decrypt(listFileCryted.read()).decode('utf8'))

list = readVideoLists()

# write videolists to encrypted file
def writeVideoLists(toWrite, printedMsg, commitMsg):
	with open('listFile.json.crypt', 'wb') as f:
		f.write(getCipher().encrypt(json.dumps(toWrite)))
	print(printedMsg)
	printList(toWrite)
	git add listFile.json.crypt and git commit -m @(commitMsg) and git push

def printList(list):
	for i, l in enumerate(list):
		print(repr(i).rjust(3), l['skip'], l['url'], l['comment'])

if len(sys.argv) > 1:
	argv1 = sys.argv[1]
	argvLen = len(sys.argv)
	if argv1 == '--help' or argv1 == '-h' or argv1 == '-?' or argv1 == '-help':
		print('env: YTD_KEY [YTD_RATE]')
		print('--help|-h|-?|-help')
		print('--print')
		print('--add URL Comment')
		print('--del No')
		print('--skip No...')
		print('--readArchive File')

	if argv1 == '--print':
		printList(list)
		print('dlArchive:', archiveFile)

	if argvLen > 3 and argv1 == '--add':
		list.append({'url': sys.argv[2], 'comment': sys.argv[3], 'skip': False})
		writeVideoLists(list, 'added', '--add')

	if argvLen > 2 and argv1 == '--skip':
		idx = 2
		while idx < argvLen:
			i = -1
			try:
				i = int(sys.argv[idx])
			except:
				sys.exit(1)

			list[i]['skip'] = not list[i]['skip']
			idx += 1
		writeVideoLists(list, 'skip adjusted', '--skip')

	if argvLen > 2 and argv1 == '--del':
		i = -1
		try:
			i = int(sys.argv[2])
		except:
			sys.exit(1)

		list.pop(i)
		writeVideoLists(list, 'deleted', '--del')

	if argvLen > 2 and argv1 == '--readArchive':
		print('using following file as new dlArchive:' , sys.argv[2])
		encryptArchive(sys.argv[2])

	sys.exit()

def getDownloadParams(url):
	result = []
	if url.startswith('https://www.youtube.com/') or url.startswith('http://www.youtube.com/'):
		result = ['-f', 'bestvideo+bestaudio']
	return result

# download newest entries of video lists
for l in list:
	if l['skip']:
		continue
	params = getDownloadParams(l['url'])
	youtube-dl @(ratelimit) --add-metadata @(params) --download-archive @(archiveFile) --dateafter 'today-20days' -- @(l['url']) or true @(sys.exit(1))
	encryptArchive(archiveFile)
	git add dlArchive.txt.crypt and git commit -m 'download happend'

# download single videos
for root, dirs, files in os.walk('urls'):
	for file in files:
		f = os.path.join(root, file)
		urls = $(cat @(f)).strip()
		print('url-file:', f)
		for url in urls.splitlines():
			print('url from file:', url)
			params = getDownloadParams(l['url'])
			youtube-dl @(ratelimit) --add-metadata @(params) --download-archive @(archiveFile) -- @(url) or true @(sys.exit(1))
			encryptArchive(archiveFile)
			git add dlArchive.txt.crypt and git commit -m 'download happend'
		rm -v -- @(f)

# publish data file
git push
