#!/usr/bin/env xonsh

import sys
import json
import os
import os.path
import tempfile
import argparse
import collections

from Crypto.Cipher import AES
from Crypto.Util import Counter
from Crypto.Protocol.KDF import PBKDF2
from Crypto.Hash import SHA256

BITS_PER_BYTE = 8
AES_HALF_BLOCK_SIZE = AES.block_size // 2

Playlist = collections.namedtuple('Playlist', ['skip', 'url', 'comment'])


def get_cipher(iv):
    """Wrapper around a symmetric cipher."""

    ctr = Counter.new(BITS_PER_BYTE * AES_HALF_BLOCK_SIZE, prefix=iv)
    key = PBKDF2($YTD_KEY.encode('utf8'), salt=b'15AUt3q2X9CdEPAx', dkLen=32)
    return AES.new(key, mode=AES.MODE_CTR, counter=ctr)


def decrypt_archive():
    """Decrypt dlArchive file of youtube-dl to temporary file and return its filename."""

    with open('dlArchive.iv.bin', 'rb') as iv_file:
        iv = iv_file.read()

    with tempfile.NamedTemporaryFile(delete=False) as tmp_dl_archive:
        with open('dlArchive.txt.crypt', 'rb') as dl_archive:
            tmp_dl_archive.write(get_cipher(iv).decrypt(dl_archive.read()))

    return tmp_dl_archive.name


def encrypt_archive(src_file_name):
    """Encrypt dlArchive file of youtube-dl and overwrite previously existing crypted file, using the given file name as source."""

    iv = os.urandom(AES_HALF_BLOCK_SIZE)

    with open('dlArchive.iv.bin', 'wb') as iv_file:
        iv_file.write(iv)

    with open(src_file_name, 'r') as src_file:
        with open('dlArchive.txt.crypt', 'wb') as dl_archive:
            dl_archive.write(get_cipher(iv).encrypt(src_file.read()))


def read_playlist_list():
    """Read list of Playlists from encrypted file."""

    with open('listFile.iv.bin', 'rb') as iv_file:
        iv = iv_file.read()

    with open('skip.json', 'rt') as skip_file:
        skip_list = json.load(skip_file)

    with open('listFile.json.crypt', 'rb') as list_file_cryted:
        urls_and_comments = json.loads(get_cipher(iv).decrypt(list_file_cryted.read()).decode('utf8'))

    return [Playlist(url=uc['url'], comment=uc['comment'], skip=(idx in skip_list)) for (idx, uc) in enumerate(urls_and_comments)]


def write_playlist_list(to_write, printed_msg, commit_msg, only_write_skip_list):
    """Write list of Playlists to encrypted file."""

    if not only_write_skip_list:
        iv = os.urandom(AES_HALF_BLOCK_SIZE)

        with open('listFile.iv.bin', 'wb') as iv_file:
            iv_file.write(iv)

        with open('listFile.json.crypt', 'wb') as f:
            urls_and_comments = [{'url': pl.url, 'comment': pl.comment} for pl in to_write]
            f.write(get_cipher(iv).encrypt(json.dumps(urls_and_comments)))

    with open('skip.json', 'wt') as skip_file:
        skip_list = [idx for (idx, pl) in enumerate(to_write) if pl.skip]
        skip_file.write(json.dumps(skip_list))

    print(printed_msg)
    print_list(to_write)

    git add listFile.json.crypt listFile.iv.bin skip.json and git commit -m @(commit_msg) and git push


def print_list(list):
    for i, l in enumerate(list):
        skip_str = 'skip' if l.skip else 'dl'
        skip_str = skip_str.rjust(5)
        print(repr(i).rjust(3), skip_str, l.url, repr(i).rjust(3), skip_str, l.comment)


def handle_skip_toggle(indices_to_toggle, video_list):
    for i in indices_to_toggle:
        video_list[i] = Playlist(url=video_list[i].url, comment=video_list[i].comment, skip=not video_list[i].skip)
    write_playlist_list(video_list, 'skip adjusted', '--skip', only_write_skip_list=True)


def get_download_params(url):
    if url.startswith('https://www.youtube.com/') or url.startswith('http://www.youtube.com/'):
        return ['--add-metadata', '-f', 'bestvideo+bestaudio']
    return []


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
    archive_file_name = decrypt_archive()

    list = read_playlist_list()

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
        print_list(list)
        print('dlArchive:', archive_file_name)
        print('Switch skips with --skip No...')
        return

    if args.skip:
        handle_skip_toggle(args.skip, list)
        return

    if args.del_arg:
        list.pop(args.del_arg)
        write_playlist_list(list, 'deleted', '--del', only_write_skip_list=False)
        return

    if args.add:
        list.append(Playlist(url=args.add[0], comment=args.add[1], skip=False))
        write_playlist_list(list, 'added', '--add', only_write_skip_list=False)
        return

    if args.readArchive:
        print('using following file as new dlArchive:', args.readArchive)
        encrypt_archive(args.readArchive)
        print('not comitting this file')
        return

    # download newest entries of video lists
    for l in list:
        if l.skip:
            continue
        params = get_download_params(l.url)
        youtube-dl @(ratelimit) @(params) --download-archive @(archive_file_name) -- @(l.url) or true @(sys.exit(1))
        encrypt_archive(archive_file_name)
        git add dlArchive.txt.crypt dlArchive.iv.bin and git commit -m 'download happend'

    # download single videos
    for root, dirs, files in os.walk('urls'):
        for file in files:
            f = os.path.join(root, file)
            urls = $(cat @(f)).strip()
            print('url-file:', f)
            for url in urls.splitlines():
                print('url from file:', url)
                params = get_download_params(url)
                youtube-dl @(ratelimit) @(params) --download-archive @(archive_file_name) -- @(url) or true @(sys.exit(1))
                encrypt_archive(archive_file_name)
                git add dlArchive.txt.crypt dlArchive.iv.bin and git commit -m 'download happend'
            rm -v -- @(f)

    # publish data file
    git push


main()
