#!/usr/bin/env xonsh

import sys
import json
import os
import os.path
import tempfile
import argparse
import collections
import filecmp

from Crypto.Cipher import AES
from Crypto.Util import Counter
from Crypto.Protocol.KDF import PBKDF2
from Crypto.Hash import SHA256

BITS_PER_BYTE = 8
AES_HALF_BLOCK_SIZE = AES.block_size // 2


def create_and_save_iv(file_name):
    iv = os.urandom(AES_HALF_BLOCK_SIZE)

    with open(file_name, 'wb') as iv_file:
        iv_file.write(iv)

    return iv


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

    cmp_file_name = decrypt_archive()
    if filecmp.cmp(src_file_name, cmp_file_name):
        print('Not overwriting dlArchive with same content')
        return

    iv = create_and_save_iv('dlArchive.iv.bin')

    with open(src_file_name, 'rb') as src_file:
        with open('dlArchive.txt.crypt', 'wb') as dl_archive:
            dl_archive.write(get_cipher(iv).encrypt(src_file.read()))


Playlist = collections.namedtuple('Playlist', ['skip', 'url', 'comment'])


class PlaylistList:
    def __init__(self):
        self._list = []
        self._read_from_files()

    def _read_from_files(self):
        with open('listFile.iv.bin', 'rb') as iv_file:
            iv = iv_file.read()

        with open('skip.json', 'rt') as skip_file:
            skip_list = json.load(skip_file)

        with open('listFile.json.crypt', 'rb') as list_file_crypted:
            urls_and_comments = json.loads(get_cipher(iv).decrypt(list_file_crypted.read()).decode('utf8'))

        for (idx, uc) in enumerate(urls_and_comments):
            self._list.append(Playlist(url=uc['url'], comment=uc['comment'], skip=(idx in skip_list)))

    def _detailed_cmp(self, other):
        if len(self._list) != len(other._list):
            return (True, True)

        skip_data_different = False
        url_or_comment_data_different = False

        for (a, b) in zip(self._list, other._list):
            if a.skip != b.skip:
                skip_data_different = True
            if a.url != b.url or a.comment != b.comment:
                url_or_comment_data_different = True

        return (skip_data_different, url_or_comment_data_different)

    def _write_to_files(self, commit_msg):
        cmp_data = PlaylistList()
        (skip_data_different, url_or_comment_data_different) = self._detailed_cmp(cmp_data)

        if url_or_comment_data_different:
            iv = create_and_save_iv('listFile.iv.bin')

            with open('listFile.json.crypt', 'wb') as f:
                urls_and_comments = [{'url': pl.url, 'comment': pl.comment} for pl in self._list]
                f.write(get_cipher(iv).encrypt(json.dumps(urls_and_comments)))

        if skip_data_different:
            with open('skip.json', 'wt') as skip_file:
                skip_list = [idx for (idx, pl) in enumerate(self._list) if pl.skip]
                skip_file.write(json.dumps(skip_list))

        git add listFile.json.crypt listFile.iv.bin skip.json and git commit -m @(commit_msg) and git push

    def print(self):
        for i, l in enumerate(self._list):
            skip_str = 'skip' if l.skip else 'dl'
            skip_str = skip_str.rjust(5)
            print(repr(i).rjust(3), skip_str, l.url, repr(i).rjust(3), skip_str, l.comment)

    def toggle_skip(self, indices_to_toggle):
        for i in indices_to_toggle:
            toggle_this = self._list[i]
            self._list[i] = Playlist(url=toggle_this.url, comment=toggle_this.comment, skip=not toggle_this.skip)

        print('skip adjusted')
        self.print()
        self._write_to_files('--skip')

    def del_playlist(self, idx):
        self._list.pop(idx)

        print('deleted')
        self.print()
        self._write_to_files('--del')

    def add_playlist(self, url, comment):
        self._list.append(Playlist(url=url, comment=comment, skip=False))

        print('added')
        self.print()
        self._write_to_files('--add')

    def enumerate_to_download(self):
        for pl in self._list:
            if not pl.skip:
                yield pl







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

    list = PlaylistList()

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
        list.print()
        print('dlArchive:', archive_file_name)
        print('Switch skips with --skip No...')
        return

    if args.skip:
        list.toggle_skip(args.skip)
        return

    if args.del_arg:
        list.del_playlist(args.del_arg)
        return

    if args.add:
        list.add_playlist(args.add[0], args.add[1])
        return

    if args.readArchive:
        print('using following file as new dlArchive:', args.readArchive)
        encrypt_archive(args.readArchive)
        print('not comitting this file')
        return

    # download newest entries of video lists
    for l in list.enumerate_to_download():
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
