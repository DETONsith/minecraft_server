#!/usr/bin/env python3
import os
import sys
import json
import shutil
import hashlib
import struct
import gzip
import uuid

# ==============================================================================
# Pure Python NBT Reader & Writer
# ==============================================================================
class NBT:
    TAG_END = 0
    TAG_BYTE = 1
    TAG_SHORT = 2
    TAG_INT = 3
    TAG_LONG = 4
    TAG_FLOAT = 5
    TAG_DOUBLE = 6
    TAG_BYTE_ARRAY = 7
    TAG_STRING = 8
    TAG_LIST = 9
    TAG_COMPOUND = 10
    TAG_INT_ARRAY = 11
    TAG_LONG_ARRAY = 12

    @classmethod
    def read(cls, data, offset=0):
        t = data[offset]
        offset += 1
        if t == cls.TAG_END:
            return None, (t, None), offset
        name_len = struct.unpack_from('>H', data, offset)[0]
        offset += 2
        name = data[offset:offset+name_len].decode('utf-8', 'replace')
        offset += name_len
        val, offset = cls.read_value(t, data, offset)
        return name, (t, val), offset

    @classmethod
    def read_value(cls, t, data, offset):
        if t == cls.TAG_BYTE:
            return struct.unpack_from('>b', data, offset)[0], offset + 1
        elif t == cls.TAG_SHORT:
            return struct.unpack_from('>h', data, offset)[0], offset + 2
        elif t == cls.TAG_INT:
            return struct.unpack_from('>i', data, offset)[0], offset + 4
        elif t == cls.TAG_LONG:
            return struct.unpack_from('>q', data, offset)[0], offset + 8
        elif t == cls.TAG_FLOAT:
            return struct.unpack_from('>f', data, offset)[0], offset + 4
        elif t == cls.TAG_DOUBLE:
            return struct.unpack_from('>d', data, offset)[0], offset + 8
        elif t == cls.TAG_BYTE_ARRAY:
            l = struct.unpack_from('>i', data, offset)[0]
            offset += 4
            return data[offset:offset+l], offset + l
        elif t == cls.TAG_STRING:
            l = struct.unpack_from('>H', data, offset)[0]
            offset += 2
            s = data[offset:offset+l].decode('utf-8', 'replace')
            return s, offset + l
        elif t == cls.TAG_LIST:
            elem_type = data[offset]
            offset += 1
            l = struct.unpack_from('>i', data, offset)[0]
            offset += 4
            res = []
            for _ in range(l):
                elem, offset = cls.read_value(elem_type, data, offset)
                res.append(elem)
            return (elem_type, res), offset
        elif t == cls.TAG_COMPOUND:
            res = {}
            while True:
                tt = data[offset]
                offset += 1
                if tt == cls.TAG_END:
                    break
                nl = struct.unpack_from('>H', data, offset)[0]
                offset += 2
                name = data[offset:offset+nl].decode('utf-8', 'replace')
                offset += nl
                val, offset = cls.read_value(tt, data, offset)
                res[name] = (tt, val)
            return res, offset
        elif t == cls.TAG_INT_ARRAY:
            l = struct.unpack_from('>i', data, offset)[0]
            offset += 4
            res = struct.unpack_from(f'>{l}i', data, offset)
            return list(res), offset + l * 4
        elif t == cls.TAG_LONG_ARRAY:
            l = struct.unpack_from('>i', data, offset)[0]
            offset += 4
            res = struct.unpack_from(f'>{l}q', data, offset)
            return list(res), offset + l * 8
        raise ValueError(f'Unknown tag {t} at {offset}')

    @classmethod
    def write_tag(cls, name, tag_tuple):
        t, val = tag_tuple
        buf = bytearray([t])
        nb = name.encode('utf-8')
        buf.extend(struct.pack('>H', len(nb)))
        buf.extend(nb)
        buf.extend(cls.write_value(t, val))
        return buf

    @classmethod
    def write_value(cls, t, val):
        if t == cls.TAG_BYTE:
            return struct.pack('>b', val)
        elif t == cls.TAG_SHORT:
            return struct.pack('>h', val)
        elif t == cls.TAG_INT:
            return struct.pack('>i', val)
        elif t == cls.TAG_LONG:
            return struct.pack('>q', val)
        elif t == cls.TAG_FLOAT:
            return struct.pack('>f', val)
        elif t == cls.TAG_DOUBLE:
            return struct.pack('>d', val)
        elif t == cls.TAG_BYTE_ARRAY:
            return struct.pack('>i', len(val)) + bytes(val)
        elif t == cls.TAG_STRING:
            sb = val.encode('utf-8')
            return struct.pack('>H', len(sb)) + sb
        elif t == cls.TAG_LIST:
            elem_type, items = val
            buf = bytearray([elem_type])
            buf.extend(struct.pack('>i', len(items)))
            for item in items:
                buf.extend(cls.write_value(elem_type, item))
            return bytes(buf)
        elif t == cls.TAG_COMPOUND:
            buf = bytearray()
            for k, (sub_t, sub_v) in val.items():
                sub_nb = k.encode('utf-8')
                buf.append(sub_t)
                buf.extend(struct.pack('>H', len(sub_nb)))
                buf.extend(sub_nb)
                buf.extend(cls.write_value(sub_t, sub_v))
            buf.append(cls.TAG_END)
            return bytes(buf)
        elif t == cls.TAG_INT_ARRAY:
            return struct.pack('>i', len(val)) + struct.pack(f'>{len(val)}i', *val)
        elif t == cls.TAG_LONG_ARRAY:
            return struct.pack('>i', len(val)) + struct.pack(f'>{len(val)}q', *val)
        raise ValueError(f'Unknown type {t}')


def get_offline_uuid(name):
    m = hashlib.md5(("OfflinePlayer:" + name).encode("utf-8")).digest()
    b = bytearray(m)
    b[6] = (b[6] & 0x0f) | 0x30
    b[8] = (b[8] & 0x3f) | 0x80
    return str(uuid.UUID(bytes=bytes(b)))


def parse_nbt_file(filepath):
    with gzip.open(filepath, 'rb') as f:
        data = f.read()
    root_name, root_tag, _ = NBT.read(data)
    return root_name, root_tag


def save_nbt_file(filepath, root_name, root_tag):
    raw_data = NBT.write_tag(root_name or '', root_tag)
    with gzip.open(filepath, 'wb') as f:
        f.write(raw_data)


def fix_world_uuids(world_dir, instance_dir=None):
    if not os.path.isdir(world_dir):
        print(f"Erro: Diretório do mundo '{world_dir}' não encontrado.")
        return

    print(f"\n[UUID-FIX] Analisando jogadores e corrigindo UUIDs offline em: {world_dir}")

    # Coletar mapeamentos de nicks
    name_map = {}  # old_uuid -> name

    # 1. Checar usernamecache.json na instância e no mundo
    possible_caches = [
        os.path.join(world_dir, "..", "usernamecache.json"),
        os.path.join(world_dir, "usernamecache.json"),
    ]
    if instance_dir:
        possible_caches.append(os.path.join(instance_dir, "usernamecache.json"))
        possible_caches.append(os.path.join(instance_dir, "saves", "New World", "usernamecache.json"))

    for cpath in possible_caches:
        if os.path.isfile(cpath):
            try:
                with open(cpath, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    for uid, name in data.items():
                        name_map[uid.lower()] = name
            except Exception as e:
                print(f"Aviso ao ler {cpath}: {e}")

    # Adicionar nicks conhecidos
    known_defaults = {
        "0d1684ed-c5c1-483f-98f6-57cf7915fde3": "Desodoman",
        "5b5eb6ea-9038-4c8a-9cc5-246457ca84b7": "DetonSith",
        "89e1a285-7dea-3805-ae9f-27932ff36f65": "DetonSith",
        "aab88f7a-7088-3f8c-a288-a69ce44e8d67": "Desodoman"
    }
    for uid, name in known_defaults.items():
        if uid.lower() not in name_map:
            name_map[uid.lower()] = name

    # Mapeamento old_uuid -> (new_uuid, name)
    uuid_translations = {}
    for old_uid, name in name_map.items():
        new_uid = get_offline_uuid(name).lower()
        if old_uid != new_uid:
            uuid_translations[old_uid] = (new_uid, name)

    print(f"[UUID-FIX] Jogadores mapeados:")
    for old_u, (new_u, name) in uuid_translations.items():
        print(f"  - Jogador: {name} | UUID Original: {old_u} -> UUID Offline: {new_u}")

    # Diretórios
    playerdata_dir = os.path.join(world_dir, "playerdata")
    stats_dir = os.path.join(world_dir, "stats")
    advancements_dir = os.path.join(world_dir, "advancements")
    data_dir = os.path.join(world_dir, "data")
    os.makedirs(playerdata_dir, exist_ok=True)
    os.makedirs(stats_dir, exist_ok=True)
    os.makedirs(advancements_dir, exist_ok=True)

    # 1. Extrair e converter NBT de playerdata
    for old_u, (new_u, name) in uuid_translations.items():
        old_dat = os.path.join(playerdata_dir, f"{old_u}.dat")
        new_dat = os.path.join(playerdata_dir, f"{new_u}.dat")

        source_dat = None
        if os.path.isfile(old_dat):
            source_dat = old_dat
        elif instance_dir and os.path.isfile(os.path.join(instance_dir, "saves", "New World", "playerdata", f"{old_u}.dat")):
            source_dat = os.path.join(instance_dir, "saves", "New World", "playerdata", f"{old_u}.dat")

        if source_dat and os.path.isfile(source_dat):
            try:
                root_name, root_tag = parse_nbt_file(source_dat)
                compound = root_tag[1]
                
                # Calcular UUIDMost e UUIDLeast para o novo UUID
                new_uuid_obj = uuid.UUID(new_u)
                new_most, new_least = struct.unpack('>qq', new_uuid_obj.bytes)
                
                # Atualizar tags internas do NBT
                compound['UUIDMost'] = (NBT.TAG_LONG, new_most)
                compound['UUIDLeast'] = (NBT.TAG_LONG, new_least)
                
                # Salvar novo .dat
                save_nbt_file(new_dat, root_name, root_tag)
                inv_count = len(compound.get('Inventory', (None, (None, [])))[1][1])
                print(f"  ✓ Playerdata convertido e salvo em {new_u}.dat ({name}) - {inv_count} itens no inventário")
            except Exception as e:
                print(f"  ✗ Erro ao converter playerdata {source_dat}: {e}")
                # Fallback para cópia direta se falhar
                shutil.copy2(source_dat, new_dat)

        # cyclic inventory
        old_cyc = os.path.join(playerdata_dir, f"{old_u}.cyclicinvo")
        new_cyc = os.path.join(playerdata_dir, f"{new_u}.cyclicinvo")
        if not os.path.isfile(old_cyc) and instance_dir:
            inst_cyc = os.path.join(instance_dir, "saves", "New World", "playerdata", f"{old_u}.cyclicinvo")
            if os.path.isfile(inst_cyc):
                old_cyc = inst_cyc
        if os.path.isfile(old_cyc):
            shutil.copy2(old_cyc, new_cyc)
            print(f"  ✓ Cyclic inventory copiado para {new_u}.cyclicinvo ({name})")

        # stats .json
        old_stat = os.path.join(stats_dir, f"{old_u}.json")
        new_stat = os.path.join(stats_dir, f"{new_u}.json")
        if not os.path.isfile(old_stat) and instance_dir:
            inst_stat = os.path.join(instance_dir, "saves", "New World", "stats", f"{old_u}.json")
            if os.path.isfile(inst_stat):
                old_stat = inst_stat
        if os.path.isfile(old_stat):
            shutil.copy2(old_stat, new_stat)
            print(f"  ✓ Stats copiados para {new_u}.json ({name})")

        # advancements .json
        old_adv = os.path.join(advancements_dir, f"{old_u}.json")
        new_adv = os.path.join(advancements_dir, f"{new_u}.json")
        if not os.path.isfile(old_adv) and instance_dir:
            inst_adv = os.path.join(instance_dir, "saves", "New World", "advancements", f"{old_u}.json")
            if os.path.isfile(inst_adv):
                old_adv = inst_adv
        if os.path.isfile(old_adv):
            shutil.copy2(old_adv, new_adv)
            print(f"  ✓ Advancements copiados para {new_u}.json ({name})")

        # data directory trackers
        if os.path.isdir(data_dir):
            for fname in os.listdir(data_dir):
                if old_u in fname:
                    old_fpath = os.path.join(data_dir, fname)
                    new_fname = fname.replace(old_u, new_u)
                    new_fpath = os.path.join(data_dir, new_fname)
                    shutil.copy2(old_fpath, new_fpath)
                    print(f"  ✓ Data tracker {fname} -> {new_fname}")

    # 2. Atualizar JSONs de BetterQuesting e FTB Lib
    target_json_dirs = [
        os.path.join(world_dir, "betterquesting"),
        os.path.join(world_dir, "data", "ftb_lib")
    ]

    for jdir in target_json_dirs:
        if os.path.isdir(jdir):
            for root, _, files in os.walk(jdir):
                for file in files:
                    if file.endswith(".json") or file.endswith(".dat"):
                        fpath = os.path.join(root, file)
                        try:
                            with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                                content = f.read()

                            modified = False
                            for old_u, (new_u, _) in uuid_translations.items():
                                if old_u in content or old_u.upper() in content:
                                    content = content.replace(old_u, new_u)
                                    content = content.replace(old_u.upper(), new_u)
                                    modified = True

                            if modified:
                                with open(fpath, "w", encoding="utf-8") as f:
                                    f.write(content)
                                print(f"  ✓ Atualizado progresso de quests/dados em {file}")
                        except Exception:
                            pass

    # 3. Atualizar usernamecache.json e usercache.json no servidor
    server_root = os.path.abspath(os.path.join(world_dir, ".."))
    server_usercache = os.path.join(server_root, "usernamecache.json")
    try:
        current_uc = {}
        if os.path.isfile(server_usercache):
            with open(server_usercache, "r", encoding="utf-8") as f:
                current_uc = json.load(f)
        for _, (new_u, name) in uuid_translations.items():
            current_uc[new_u] = name
        # Garantir conhecidos
        current_uc[get_offline_uuid("Desodoman")] = "Desodoman"
        current_uc[get_offline_uuid("DetonSith")] = "DetonSith"
        with open(server_usercache, "w", encoding="utf-8") as f:
            json.dump(current_uc, f, indent=2)
        print("  ✓ usernamecache.json atualizado no servidor.")
    except Exception as e:
        print(f"Aviso ao salvar usernamecache: {e}")

    # 4. Atualizar ops.json se necessário
    ops_file = os.path.join(server_root, "ops.json")
    try:
        ops_data = []
        if os.path.isfile(ops_file):
            with open(ops_file, "r", encoding="utf-8") as f:
                try:
                    ops_data = json.load(f)
                except Exception:
                    ops_data = []
        existing_ops = {op.get("name"): op for op in ops_data if isinstance(op, dict)}
        for op_name in ["Desodoman", "DetonSith"]:
            op_uuid = get_offline_uuid(op_name)
            if op_name not in existing_ops:
                ops_data.append({
                    "uuid": op_uuid,
                    "name": op_name,
                    "level": 4,
                    "bypassesPlayerLimit": False
                })
        with open(ops_file, "w", encoding="utf-8") as f:
            json.dump(ops_data, f, indent=2)
        print("  ✓ ops.json configurado com permissões de administrador (OP).")
    except Exception as e:
        print(f"Aviso ao configurar ops.json: {e}")

    print("[UUID-FIX] ✓ Migração de UUIDs offline concluída com sucesso!\n")


if __name__ == "__main__":
    w_dir = sys.argv[1] if len(sys.argv) > 1 else "/home/giovani-goncalves/projetos/minecraft_server/minecraft/server/world"
    inst_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.sklauncher/instances/stoneblock")
    fix_world_uuids(w_dir, inst_dir)
