#!/usr/bin/env xonsh

import sys
import json
import os
import os.path
import tempfile
import argparse

from Crypto.Cipher import AES
from Crypto.Util import Counter
from Crypto.Protocol.KDF import PBKDF2
from Crypto.Hash import SHA256

BITS_PER_BYTE = 8
AES_HALF_BLOCK_SIZE = AES.block_size // 2

# wrapper around a symmetric cipher
def getCipher(iv):
	ctr = Counter.new(BITS_PER_BYTE * AES_HALF_BLOCK_SIZE, prefix=iv)
	key = PBKDF2($YTD_KEY.encode('utf8'), salt=b'15AUt3q2X9CdEPAx', dkLen=32)
	return AES.new(key, mode=AES.MODE_CTR, counter=ctr)

# decrypt dlArchive file of youtube-dl to temporary file and return its filename
def decryptArchive():
	with open('dlArchive.iv.bin', 'rb') as ivFile:
		iv = ivFile.read()

	with tempfile.NamedTemporaryFile(delete=False) as tmpDlArchive:
		with open('dlArchive.txt.crypt', 'rb') as dlArchive:
			tmpDlArchive.write(getCipher(iv).decrypt(dlArchive.read()))

	return tmpDlArchive.name

# encrypt dlArchive file of youtube-dl and overwrite previously existing crypted file, using the given file name as source
def encryptArchive(srcFileName):
	iv = os.urandom(AES_HALF_BLOCK_SIZE)

	with open('dlArchive.iv.bin', 'wb') as ivFile:
		ivFile.write(iv)

	with open(srcFileName, 'r') as srcFile:
		with open('dlArchive.txt.crypt', 'wb') as dlArchive:
			dlArchive.write(getCipher(iv).encrypt(srcFile.read()))

# read videolist from encrypted file
def readVideoList():
	with open('listFile.iv.bin', 'rb') as ivFile:
		iv = ivFile.read()

	with open('listFile.json.crypt', 'rb') as listFileCryted:
		return json.loads(getCipher(iv).decrypt(listFileCryted.read()).decode('utf8'))

# write videolist to encrypted file
def writeVideoList(toWrite, printedMsg, commitMsg):
	iv = os.urandom(AES_HALF_BLOCK_SIZE)

	with open('listFile.iv.bin', 'wb') as ivFile:
		ivFile.write(iv)

	with open('listFile.json.crypt', 'wb') as f:
		f.write(getCipher(iv).encrypt(json.dumps(toWrite)))

	print(printedMsg)
	printList(toWrite)

	git add listFile.json.crypt listFile.iv.bin and git commit -m @(commitMsg) and git push

def printList(list):
	for i, l in enumerate(list):
		skip_str = 'skip' if l['skip'] else 'dl'
		skip_str = skip_str.rjust(5)
		print(repr(i).rjust(3), skip_str, l['url'], l['comment'])

def handleSkipToggle(indexList, videoList):
	for i in indexList:
		videoList[i]['skip'] = not videoList[i]['skip']
	writeVideoList(videoList, 'skip adjusted', '--skip')

def getDownloadParams(url):
	result = []
	if url.startswith('https://www.youtube.com/') or url.startswith('http://www.youtube.com/'):
		result = ['--add-metadata', '-f', 'bestvideo+bestaudio']
	return result

def main():
	# check if symmetric cipher key is set in env
	if not 'YTD_KEY' in ${...}:
		print('please set YTD_KEY according to the server:')
		sys.exit(1)

	# read optional download speed rate limiting
	ratelimit = []
	if 'YTD_RATE' in ${...}:
		ratelimit = ['-r', $YTD_RATE]

	# update data files
	git pull --no-rebase or true @(sys.exit(1))

	# dlArchive file of youtube-dl
	archiveFile = decryptArchive()

	list = readVideoList()

	parser = argparse.ArgumentParser()
	parser.add_argument('-?', action='help')
	group = parser.add_mutually_exclusive_group()
	group.add_argument('--print', action='store_true')
	group.add_argument('--list', action='store_true', dest='print')
	group.add_argument('--skip', type=int, nargs='+')
	group.add_argument('--del', type=int, dest='del_arg')
	group.add_argument('--add', type=str, nargs=2, metavar=('URL', 'Label'))
	group.add_argument('--readArchive', type=str)
	args = parser.parse_args()

	if args.print:
		printList(list)
		print('dlArchive:', archiveFile)
		print('Switch skips with --skip No...')
		return

	if args.skip:
		handleSkipToggle(args.skip, list)
		return

	if args.del_arg:
		list.pop(args.del_arg)
		writeVideoList(list, 'deleted', '--del')
		return

	if args.add:
		list.append({'url': args.add[0], 'comment': args.add[1], 'skip': False})
		writeVideoList(list, 'added', '--add')
		return

	if args.readArchive:
		print('using following file as new dlArchive:', args.readArchive)
		encryptArchive(args.readArchive)
		print('not comitting this file')
		return

	# download newest entries of video lists
	for l in list:
		if l['skip']:
			continue
		params = getDownloadParams(l['url'])
		youtube-dl @(ratelimit) @(params) --download-archive @(archiveFile) -- @(l['url']) or true @(sys.exit(1))
		encryptArchive(archiveFile)
		git add dlArchive.txt.crypt dlArchive.iv.bin and git commit -m 'download happend'

	# download single videos
	for root, dirs, files in os.walk('urls'):
		for file in files:
			f = os.path.join(root, file)
			urls = $(cat @(f)).strip()
			print('url-file:', f)
			for url in urls.splitlines():
				print('url from file:', url)
				params = getDownloadParams(url)
				youtube-dl @(ratelimit) @(params) --download-archive @(archiveFile) -- @(url) or true @(sys.exit(1))
				encryptArchive(archiveFile)
				git add dlArchive.txt.crypt dlArchive.iv.bin and git commit -m 'download happend'
			rm -v -- @(f)

	# publish data file
	git push

main()
