# -*- coding: utf-8 -*-
"""
WinPulse 7.1 - структурная сверка. Только чтение, ничего не запускает.
Запуск: python AUDIT.py [путь]
"""
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1
                       else os.path.dirname(os.path.abspath(__file__)))

LABELS = {
    'lib/desktop_io.cmd': 'choice desktop_choice next_key input desktop_input wait receive',
    'lib/blocks.cmd': """BLOCKS_DATA BLOCKS_LOAD BLOCKS_PARSE BLOCKS_NORM BLOCKS_CLEAR BLOCKS_FLIP BLOCKS_RANGE BLOCKS_TOGGLE BLOCKS_ALL BLOCKS_NEW BLOCKS_PACK BLOCKS_PRESET BLOCKS_CONFLICT BLOCKS_VERDICT BLOCKS_VERDICT_ALL BLOCKS_SELSTAT BLOCKS_PLAN BLOCKS_SHOW BLOCKS_APPLY""", 
    'winpulse.bat': """PARSE_ARGS VALIDATE_PATH LOAD_PREFS SELFTEST ST_MOD ST_PS
        MENU_SELFTEST MS_CHECK DETECT_ALL_MAIN POST_DETECT_WARN AGREEMENT
        BITLOCKER_GATE MAIN_MENU MENU_ADV MENU_NOVICE MENU_DEFS DISPATCH
        NOVICE_TO_ADV TOOL_STATUS TOOL_DIAG TOOL_MAINT TOOL_RESTORE
        TOOL_ROLLBACK TOOL_PANELS TOOL_BENCH TOOL_BOOTTIME TOOL_HISTORY
        TOOL_MATRIX TOOL_DETECTREPAIR TOOL_SETTINGS TOOL_SYSINFO TOOL_SEARCH
        DOC_README DOC_MANUAL DOC_EXTERNAL DOC_MISSING DOC_AGREEMENT
        SHOW_USAGE MODE_PREP MODE_LITE MODE_MINIMUM MODE_MEDIUM MODE_WORK
        MODE_MAXIMUM EXP_MENU EXP_DONE EXP_BACK MODE_SUMMARY TUTORIAL
        LOCK_OK LOCK_EXISTS EXIT EXIT_EARLY TOOL_SMART TOOL_AUTORUN TOOL_FRAMETIME""",
    'lib/core.cmd': """MSG OK FAIL SKIP WARN HEAD PLAN CONFIRM SNAP_REG REG_SET
        REG_DEL REG_KEY SC_SET SC_STOP SC_START BCD_SNAP BCD_SET BCD_DEL
        POWER_SCHEME POWER_SET NETSH_TCP NETSH_SUPP NET_FLUSH FSUTIL_SET
        TASK_DISABLE TASK_ENABLE PS_RUN BLOCK_BEGIN BLOCK_END AGG_BEGIN
        AGG_END IRREVERSIBLE PURGE_FILES PAUSE_SAFE PURGE_DIR DISM_RUN""",
    'lib/detect.cmd': """DETECT_ALL DETECT_LOAD LOAD_KV_PFX DETECT_TIER1 DNUM
        DETECT_MISS DETECT_AUDIT DETECT_TIER2 DETECT_MERGE DETECT_TIER3
        DETECT_FALLBACK DETECT_DEFAULTS DETECT_SANITIZE DETECT_OS_FIX
        DETECT_ENV DETECT_CLASSIFY DETECT_HKCU DETECT_TIER_LABEL
        DETECT_SOURCES_FIX DQ DETECT_SYSINFO DETECT_REPAIR""",
    'lib/backup.cmd': """LOAD_KV SESSION_INIT SESSION_ROTATE SESSION_LIST
        RP_CLEAR RP_REQUIRE RP_MENU MM_SET DEF_EXCL DEF_SET REGACL_SET
        APPX_REMOVE HIBER_SET RESERVED_SET BCD_SUSPEND POWER_ULTIMATE
        ROLLBACK_MENU RB_PICK_SESSION RB_GROUPS RB_INIT ROLLBACK_FULL
        ROLLBACK_GROUP RB_RUN RB_SUMMARY RB_HEX2DEC CLASSIFY REPLAY_LINE RP_LNKMOVE RB_AUTORUN PROVISIONED_REMOVE""",
    'lib/guard.cmd': """G_INIT G_HARD G_SOFT_LOG G_INFO G_CONFIRM G_ADVANCED
        G_RAM G_RAM_SOFT G_SSD G_ALLSSD G_NOTLAPTOP G_ACPOWER G_CPU_HYBRID
        G_CPU_OLD G_GPU_VENDOR G_HWID G_BUILD G_SECURITY_REFRESH
        G_SECURITY_INVALIDATE G_AV G_AV_THIRD G_TAMPER G_DISKSPACE
        G_NETWORK G_GLOBAL G_BANNER G_SUMMARY G_MVERDICT G_MATRIX""",
    'lib/tweaks_safe.cmd': """NET_IF_LOAD IFACE_SET T_TELEMETRY T_NET_STD
        T_NET_PORTS T_POWER T_POWER_THROTTLE T_UWP T_SCHTASKS
        T_DEFENDER_EXC T_SERVICES T_SPOOLER T_DEFRAG MAINT_PATHS T_VISUAL
        T_GAMING T_UX T_WORK T_MAINT T_INPUT T_PRIVACY_EXT T_WEBDAV""",
    'lib/tweaks_warn.cmd': """POWER_HAS T_PRIORITY T_MEMORY T_MMCSS
        T_POWER_HIBER T_POWER_DISK T_POWER_TIMER T_RESERVED T_WORK_IFEO
        T_UX_CHAT T_MOUSE T_TIMERS T_NDU T_GAMEBAR_RT T_SERVICES_XBOX
        T_AUDIO T_WDI T_STORPORT T_PREFETCH T_SYSMAIN T_VISUAL_AGG
        T_NET_GLOBAL""",
    'lib/tweaks_danger.cmd': """GPU_CLASS_LOAD T_VBS T_MITIGATIONS
        T_BCD_TIMERS T_BCD_TSC T_BCD_BOOT T_GPU_ULPS T_GPU_HDCP T_MSI_GPU""",
    'lib/tweaks_exp.cmd': """E_DWM E_NX E_PAGING_ENC E_DEF_SCRIPT
        E_TSC_LEGACY E_SEHOP E_HETERO E_DEF_RT E_CSTATES E_POOL
        E_SUPERFETCH E_ULTIMATE""",
    'lib/tools.cmd': """NORM_DWORD CHK SHOW_VAL CHK_SVC CHK_BCD SHOW_BCD
        CHK_POWER CHK_TASKS CHECK_STATUS ASK_NUM BENCH_EXEC BENCH_SILENT
        BENCH_LIST BENCH_CLEAR_NS BENCH_REPORT BENCH_DELTA BENCH_DIFF_BODY
        BENCH_AUTO_COMPARE BENCH_MENU BOOT_TIME DIAGNOSTICS_MENU
        SEARCH_DOCS UNDO_HISTORY SAVE_PREFS SETTINGS_MENU
        SYSTEM_INFO_SCREEN SMART_SCREEN AUTORUN_SCREEN FRAMETIME_SCREEN CHK_NIC CHK_NIC_ONE""",
}
PSVERBS = """get-engine get-detect get-detect-api get-interfaces get-gpuclass
    get-security get-benchmark get-boottime get-tasks get-mmagent
    get-defender get-restorepoints do-regacl do-restorepoint do-appx
    do-mmagent do-defender get-smart get-autorun get-features do-provisioned get-nic get-frametime snapshot-task snapshot-reg rotate-sessions session-key""".split()
DOCFILES = ['README.txt', 'Main/MANUAL_STEPS.txt',
            'Main/EXTERNAL_TOOLS.txt', 'Main/TWEAKS_INVENTORY.txt']
TOTALS = {'lib/tweaks_safe.cmd': 148, 'lib/tweaks_warn.cmd': 116,
          'lib/tweaks_danger.cmd': 14, 'lib/tweaks_exp.cmd': 14}
DYN = {'UWP': 13}
BADWORDS = ['选一', 'параметров differ', 'journalировать',
            'CPPCpreferred', 'тыправишь', 'КРИТИЧНО: Windhawk требует']
INVIS = {0xA0, 0xAD, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2060,
         0x202F, 0x205F, 0x3000, 0xFEFF, 0xFFFD}
SMART = {0x2018, 0x2019, 0x201C, 0x201D, 0x201E, 0xFF08, 0xFF09,
         0xFF1A, 0xFF0C, 0xFF1B, 0x2212, 0x2011}

ERR = []
WRN = []


def grab(rel):
    p = os.path.join(ROOT, rel.replace('/', os.sep))
    if not os.path.isfile(p):
        return None, None
    blob = open(p, 'rb').read()
    body = blob.decode('utf-8-sig', errors='replace')
    return blob, body.replace('\r\n', '\n').replace('\r', '\n')


def main():
    print('=' * 64)
    print(' WinPulse 7.1 AUDIT   ROOT:', ROOT)
    print('=' * 64)
    blobs, texts = {}, {}

    print('\n[1] Файлы и кодировки')
    for rel in list(LABELS) + ['lib/wp.ps1'] + DOCFILES:
        blob, body = grab(rel)
        if blob is None:
            (ERR if rel not in DOCFILES or rel.endswith('TWEAKS_INVENTORY.txt') else WRN).append('нет файла ' + rel)
            print('   MISSING %s' % rel)
            continue
        blobs[rel], texts[rel] = blob, body
        want = rel.endswith(('.ps1', '.txt'))
        has = blob[:3] == b'\xef\xbb\xbf'
        lf = blob.replace(b'\r\n', b'').count(b'\n')
        prob = []
        if has != want:
            prob.append('BOM' if has else 'нет BOM')
        if lf:
            prob.append('LF %d' % lf)
        if prob:
            ERR.append('%s: %s' % (rel, ', '.join(prob)))
        print('   %-28s %7d %s' % (rel, len(blob), 'OK' if not prob else 'FAIL ' + ','.join(prob)))

    print('\n[2] Метки')
    found = {}
    for rel, want in LABELS.items():
        if rel not in texts:
            continue
        got = re.findall(r'(?m)^[ \t]*:([A-Za-z_][A-Za-z0-9_]*)[ \t]*$', texts[rel])
        for n, line in enumerate(texts[rel].splitlines(), 1):
            if re.match(r'^\s*:[A-Za-z_][A-Za-z0-9_]*\s+\S', line):
                ERR.append('%s:%d команды на строке метки' % (rel, n))
        found[rel] = set(got)
        dup = sorted({x for x in got if got.count(x) > 1})
        miss = [w for w in want.split() if w not in found[rel]]
        if dup:
            ERR.append('%s: дубли меток %s' % (rel, dup))
        if miss:
            ERR.append('%s: нет меток %s' % (rel, ' '.join(miss)))
        print('   %-28s %3d меток, нет %d, дублей %d' % (rel, len(got), len(miss), len(dup)))

    print('\n[3] wp.ps1')
    if 'lib/wp.ps1' in texts:
        ps = texts['lib/wp.ps1']
        gone = [v for v in PSVERBS if ("'%s' {" % v) not in ps]
        if gone:
            ERR.append('wp.ps1: нет verb ' + ' '.join(gone))
        if '$env:WP_LIB' not in ps:
            ERR.append('wp.ps1: нет guard')
        for n, line in enumerate(ps.split('\n'), 1):
            if line.lstrip().startswith('::'):
                ERR.append('wp.ps1:%d "::" не комментарий PowerShell' % n)
        print('   verb %d/%d, guard %s' % (len(PSVERBS) - len(gone), len(PSVERBS),
                                          'есть' if '$env:WP_LIB' in ps else 'НЕТ'))
    else:
        print('   файл не прочитан')

    print('\n[4] Цели вызовов')
    pat = re.compile(r'call\s+"%WP_LIB%\\([a-z_]+\.cmd)"\s+:([A-Za-z0-9_]+)')
    n_all = n_bad = 0
    for rel, body in texts.items():
        if not rel.endswith(('.bat', '.cmd')):
            continue
        for line in body.split('\n'):
            low = line.strip().lower()
            if low.startswith('rem') or low.startswith('::'):
                continue
            for mod, lab in pat.findall(line):
                n_all += 1
                tgt = 'lib/' + mod
                if tgt in found and lab not in found[tgt]:
                    ERR.append('%s -> %s:%s нет метки' % (rel, mod, lab))
                    n_bad += 1
        for lab in re.findall(r'(?m)^\s*call\s+:([A-Za-z0-9_]+)', body):
            if rel in found and lab not in found[rel]:
                ERR.append('%s: call :%s без метки' % (rel, lab))
                n_bad += 1
    print('   внешних %d, битых %d' % (n_all, n_bad))

    print('\n[5] Артефакты и символы')
    for rel, body in texts.items():
        if 'ПРОДОЛЖЕНИЕ СЛЕДУЕТ' in body:
            ERR.append(rel + ': маркер продолжения')
        if not rel.endswith(('.bat', '.cmd')):
            continue
        depth = 0
        for n, line in enumerate(body.split('\n'), 1):
            low = line.strip().lower()
            cm = low.startswith('rem') or low.startswith('::')
            if re.match(r'^\s*(@@|\+|-|diff |index )', line):
                ERR.append('%s:%d мусор от диффа: %s' % (rel, n, line.strip()[:60]))
            if re.match(r'^ \S', line):
                ERR.append('%s:%d ведущий пробел - контекст диффа' % (rel, n))
            for c, ch in enumerate(line, 1):
                cp = ord(ch)
                if cp < 0x80 or 0x400 <= cp <= 0x4FF:
                    continue
                if cp in INVIS:
                    ERR.append('%s:%d:%d невидимый U+%04X' % (rel, n, c, cp))
                elif not cm and cp in SMART:
                    ERR.append('%s:%d:%d типографика U+%04X' % (rel, n, c, cp))
            if cm:
                continue
            code = re.sub(r'"[^"]*"', '""', re.sub(r'\^[()]', '', line))
            depth += code.count('(') - code.count(')')
            if depth < 0:
                ERR.append('%s:%d скобки в минус' % (rel, n))
                depth = 0
        if depth:
            ERR.append('%s: незакрытых скобок %d' % (rel, depth))
    print('   проверено %d файлов' % len(texts))

    print('\n[6] Карта меню')
    if 'winpulse.bat' in texts:
        main_bat = texts['winpulse.bat']
        for kn, mn in (('AM_KEYS', 'AM_MAP'), ('NV_KEYS', 'NV_MAP')):
            k = re.findall(r'set\s+"%s=([^"]*)"' % kn, main_bat)
            m = re.findall(r'set\s+"%s=([^"]*)"' % mn, main_bat)
            if not k or not m:
                ERR.append('нет %s/%s' % (kn, mn))
                continue
            if len(k) > 1:
                ERR.append('%s определён %d раз' % (kn, len(k)))
            pairs = m[0].split()
            keys = k[0]
            pk = [p.split(':')[0] for p in pairs]
            if len(keys) != len(pairs):
                ERR.append('%s: клавиш %d, пар %d' % (kn, len(keys), len(pairs)))
            for ch in keys:
                if pk.count(ch) != 1:
                    ERR.append('%s: клавиша %s пар %d' % (kn, ch, pk.count(ch)))
            for p in pairs:
                if ':' in p and p.split(':', 1)[1] not in found.get('winpulse.bat', set()):
                    ERR.append('%s: цель %s не метка' % (kn, p))
            print('   %s: %d клавиш, %d пар' % (kn, len(keys), len(pairs)))

    print('\n[7] Счётчики блоков')
    inv = {}
    if 'Main/TWEAKS_INVENTORY.txt' in texts:
        owners = {}
        inventory = texts['Main/TWEAKS_INVENTORY.txt']
        headers = list(re.finditer(r'(?m)^\[(B\d+)\].*$', inventory))
        block_ids = [h.group(1) for h in headers]
        if len(block_ids) != len(set(block_ids)):
            ERR.append('повтор номера блока в инвентаре')
        for index, header in enumerate(headers):
            parsed = re.fullmatch(r'\[(B\d+)\]\s+(\w+)\s+\w+\s+(\d+)\s+ops?\s+ID (\d+)(?:-(\d+))?\s*', header.group())
            if not parsed:
                ERR.append('неверный заголовок блока: ' + header.group())
                continue
            block, name, count, first, last = parsed.groups()
            if name in inv:
                ERR.append('дубль в инвентаре: ' + name)
            inv[name] = int(count)
            first, last = int(first), int(last or first)
            if last - first + 1 != inv[name]:
                ERR.append('диапазон ID не совпадает с числом операций: ' + block)
            end = headers[index + 1].start() if index + 1 < len(headers) else len(inventory)
            details = []
            for row in re.finditer(r'(?m)^[ \t]*(\d{3})(?:-(\d{3}))?[ \t]+[A-Z]', inventory[header.end():end]):
                details.extend(range(int(row[1]), int(row[2] or row[1]) + 1))
            if details != list(range(first, last + 1)):
                ERR.append('строки операций не совпадают с диапазоном ID: ' + block)
            for op in range(first, last + 1):
                if op in owners:
                    ERR.append('ID %d встречается в %s и %s' % (op, owners[op], block))
                owners[op] = block
    seen = {}
    for rel, want in TOTALS.items():
        if rel not in texts:
            continue
        body = texts[rel]
        blocks = re.findall(r':BLOCK_BEGIN\s+"([A-Z_0-9]+)"\s+(\S+)', body)
        total = 0
        for name, exp in blocks:
            if exp.isdigit():
                val = int(exp)
            elif name in DYN:
                val = DYN[name]
            else:
                ERR.append('%s %s: ожидание %s не число' % (rel, name, exp))
                continue
            total += val
            seen[name] = val
            if name in inv and inv[name] != val:
                ERR.append('%s %s: код %d, инвентарь %d' % (rel, name, val, inv[name]))
        tail = re.search(r'END OF FILE\s*\|\s*Всего твиков в файле:\s*(\d+)', body)
        dec = int(tail.group(1)) if tail else -1
        if total != want or dec != want:
            ERR.append('%s: сумма %d, END OF FILE %d, надо %d' % (rel, total, dec, want))
        print('   %-26s блоков %2d сумма %3d футер %3d надо %3d' % (rel, len(blocks), total, dec, want))
    if 'Main/TWEAKS_INVENTORY.txt' in texts:
        a = sorted(set(inv) - set(seen))
        b = sorted(set(seen) - set(inv))
        if a:
            ERR.append('в инвентаре без кода: %s' % a)
        if b:
            ERR.append('в коде без инвентаря: %s' % b)
        print('   инвентарь %d блоков, расхождений имён %d' % (len(inv), len(a) + len(b)))

    print('\n[8] Документы')
    for rel in DOCFILES:
        if rel not in texts:
            continue
        lines = texts[rel].split('\n')
        h = sum(1 for l in lines if re.match(r'^@@\s', l))
        plus = sum(1 for l in lines if l.startswith('+'))
        minus = sum(1 for l in lines
                    if not re.match(r'^-{3,}', l) and re.match(r'^-(\s{2,}|[^\s-]|$)', l))
        tw = [w for w in BADWORDS if w in texts[rel]]
        if h or plus:
            ERR.append('%s: дифф-мусор @@=%d +%d -%d' % (rel, h, plus, minus))
        if tw:
            ERR.append('%s: %s' % (rel, tw))
        print('   %-28s @@=%d +%d -%d слов %d' % (rel, h, plus, minus, len(tw)))

    print('\n' + '=' * 64)
    print(' ОШИБОК %d, ПРЕДУПРЕЖДЕНИЙ %d' % (len(ERR), len(WRN)))
    print('=' * 64)
    for e in ERR:
        print('  ERROR ' + e)
    for w in WRN:
        print('  WARN  ' + w)
    if not ERR:
        print(' Структура чистая. Дальше: winpulse.bat /dryrun /advanced')
    return 1 if ERR else 0


if __name__ == '__main__':
    sys.exit(main())

# END OF FILE | Всего твиков в файле: 0
