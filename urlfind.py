#!/usr/bin/env python3

import re
import os
import os.path
import sys


def main():
    already_found = []
    url_matcher = re.compile(r'(https?://(www.)?)?(youtu.be|youtube.(com|de|ch|at))/watch\?v=[-_0-9A-Za-z]{11}')
    backup_matcher = re.compile(r'youtu')

    argc = len(sys.argv)
    if argc == 1:
        whole_input = sys.stdin.read()
    elif argc == 2:
        with open(sys.argv[1], mode='rt', encoding='utf8') as inf:
            whole_input = inf.read()
    else:
        raise Exception()

    os.makedirs('./urls', exist_ok=True)

    num_found = 0
    filename_ctr = 0
    for match in url_matcher.finditer(whole_input):
        num_found += 1
        already_found.append((match.start(), match.end()))
        written = False
        while (not written) and (filename_ctr < 31337):
            try:
                with open(os.path.join('./urls/', '{0}.txt'.format(filename_ctr)), mode='xt', encoding='utf8') as outf:
                    print(match.group(0), file=outf)
                written = True
            except OSError:
                pass
            filename_ctr += 1
        if filename_ctr >= 31337:
            print("Error: hit infinite loop while attempting to create files. Exiting.", file=sys.stderr)
            sys.exit(1)

    num_backup_candidates = 0
    whole_len = len(whole_input)
    for match in backup_matcher.finditer(whole_input):
        ms = match.start()
        me = match.end()
        for (s, e) in already_found:
            if ms >= s and me <= e:
                break
        else:
            s = max(ms - 33, 0)
            e = min(me + 33, whole_len)
            num_backup_candidates += 1
            print('found unmatched candidate: ' + whole_input[s:e])

    print('found {0} unmatched candidates and created {1} URL files'.format(num_backup_candidates, num_found))
    print('done')


if __name__ == "__main__":
    main()
