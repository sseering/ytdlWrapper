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
	print('please set YTD_KEY according to the server')
	sys.exit(1)

# wrapper around a symmetric cipher
def getCipher():
	ctr = Counter.new(128)
	key = PBKDF2($YTD_KEY.encode('utf8'), salt=b'15AUt3q2X9CdEPAx', dkLen=32)
	return AES.new(key, mode=AES.MODE_CTR, counter=ctr)

# update data files
git pull --no-rebase or true @(sys.exit(1))

# read videolists from encrypted file
list = []
with open('listFile.json.crypt', 'rb') as listFileCryted:
	listFile = getCipher().decrypt(listFileCryted.read())
	list = json.loads(listFile.decode('utf8'))

# decrypt dlArchive file of youtube-dl to temporary file
with tempfile.NamedTemporaryFile(delete=False) as tmpDlArchive:
	with open('dlArchive.txt.crypt', 'rb') as dlArchive:
		tmpDlArchive.write(getCipher().decrypt(dlArchive.read()))

def printList(list):
	for i, l in enumerate(list):
		print(repr(i).rjust(3), l['url'], l['comment'])

if len(sys.argv) > 1:
	if sys.argv[1] == '--print':
		printList(list)

	if len(sys.argv) > 3 and sys.argv[1] == '--add':
		list.append({'url': sys.argv[2], 'comment': sys.argv[3]})
		with open('listFile.json.crypt', 'wb') as f:
			f.write(getCipher().encrypt(json.dumps(list)))
		print('added')
		printList(list)
		git add listFile.json.crypt and git commit -m --add and git push

	if len(sys.argv) > 2 and sys.argv[1] == '--del':
		i = -1
		try:
			i = int(sys.argv[2])
		except:
			sys.exit(1)

		list.pop(i)
		with open('listFile.json.crypt', 'wb') as f:
			f.write(getCipher().encrypt(json.dumps(list)))
		print('deleted')
		printList(list)
		git add listFile.json.crypt and git commit -m --del and git push

	sys.exit()

# download newest entries of video lists
for l in list:
	youtube-dl --abort-on-error --embed-thumbnail --add-metadata -f bestvideo+bestaudio --download-archive @(tmpDlArchive.name) --dateafter 'today-20days' -- @(l['url']) or true @(sys.exit(1))

# download single videos
for root, dirs, files in os.walk('urls'):
	for file in files:
		f = os.path.join(root, file)
		url = $(cat @(f)).strip()
		print(f)
		youtube-dl --abort-on-error --embed-thumbnail --add-metadata -f bestvideo+bestaudio --download-archive @(tmpDlArchive.name) -- @(url) or true @(sys.exit(1))
		rm -v -- @(f)

# reencrypt dlArchive file of youtube-dl from temporary file
with open(tmpDlArchive.name, 'r') as srcFile:
	with open('dlArchive.txt.crypt', 'wb') as dlArchive:
		dlArchive.write(getCipher().encrypt(srcFile.read()))

# publish data file
git add dlArchive.txt.crypt and git commit -m 'download happend' and git push
