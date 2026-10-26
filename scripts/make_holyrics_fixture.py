#!/usr/bin/env python3
"""Buduje shared/fixtures/holyrics-music-list.mufl: strumień Java ObjectStream jak eksport Holyrics
(ArrayList z obiektami com.limagiran.holyrics.model.Music), z wymyślonymi tekstami.

Plik sprawdzają testy Swift (SharedFixturesTests); oczekiwany wynik jest w holyrics.json.
Uruchomienie: python3 -I scripts/make_holyrics_fixture.py
"""
import os
import struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.join(ROOT, "shared/fixtures/holyrics-music-list.mufl")

SONGS = [
    {"id": 101, "favorite": True, "title": "Idziemy razem", "author": "Autor Testowy", "artist": "", "tom": "D",
     "note": "Wejście", "lyrics": "##(Verse 1)\r\nIdziemy razem przez pola,\r\nsłońce nad nami świeci.\r\n\r\n##(Chorus)\r\nŚpiewaj radośnie,\r\nniech się niesie."},
    {"id": 102, "favorite": False, "title": "  Cicha łąka ", "author": "", "artist": "Zespół Przykładowy", "tom": "",
     "note": "", "lyrics": "##(Verse)\nNad cichą łąką wieczór\n\n##(Bridge 2)\nGwiazdy nad nami\n\n##(Ending)\nAmen"},
    {"id": 103, "favorite": False, "title": "", "author": "", "artist": "", "tom": "Em",
     "note": "", "lyrics": "##(Intro)\nLa la la\n\n##(Pre-Chorus)\nJuż za chwilę\n\n##(Solo gitary)\nTylko muzyka"},
]


class Stream:
    def __init__(self):
        self.data = bytearray(b"\xac\xed\x00\x05")
        self.handles = 0
        self.strings = {}

    def u8(self, v): self.data += bytes([v])
    def u16(self, v): self.data += struct.pack(">H", v)
    def u32(self, v): self.data += struct.pack(">I", v)
    def i64(self, v): self.data += struct.pack(">q", v)
    def utf(self, text):
        raw = text.encode("utf-8")
        self.u16(len(raw))
        self.data += raw

    def new_handle(self):
        handle = self.handles
        self.handles += 1
        return handle

    def reference(self, handle):
        self.u8(0x71)
        self.u32(0x7E0000 + handle)

    def string(self, text):
        """Napis; powtórzony jest zapisywany jako referencja (jak w Javie)."""
        if text in self.strings:
            return self.reference(self.strings[text])
        self.u8(0x74)
        self.strings[text] = self.new_handle()
        self.utf(text)


def build():
    s = Stream()
    # ArrayList: klasa z writeObject (flagi 0x03), pole int size, potem blok z pojemnością i elementy.
    s.u8(0x73)
    s.u8(0x72); s.new_handle(); s.utf("java.util.ArrayList"); s.i64(0x7881D21D99C7619D); s.u8(0x03)
    s.u16(1); s.u8(ord("I")); s.utf("size")
    s.u8(0x78); s.u8(0x70)
    s.new_handle()  # obiekt ArrayList
    s.u32(len(SONGS))
    s.u8(0x77); s.u8(4); s.u32(len(SONGS))
    music_class = None
    fields = [("J", "id"), ("Z", "favorite"), ("L", "title"), ("L", "author"), ("L", "artist"), ("L", "lyrics"), ("L", "note"), ("L", "tom")]
    for song in SONGS:
        s.u8(0x73)
        if music_class is None:
            s.u8(0x72); music_class = s.new_handle(); s.utf("com.limagiran.holyrics.model.Music"); s.i64(1); s.u8(0x02)
            s.u16(len(fields))
            for type_code, name in fields:
                s.u8(ord(type_code)); s.utf(name)
                if type_code == "L":
                    s.string("Ljava/lang/String;")
            s.u8(0x78); s.u8(0x70)
        else:
            s.reference(music_class)
        s.new_handle()  # obiekt Music
        s.i64(song["id"]); s.u8(1 if song["favorite"] else 0)
        for type_code, name in fields:
            if type_code == "L":
                s.string(song[name])
    s.u8(0x78)
    return bytes(s.data)


if __name__ == "__main__":
    data = build()
    with open(OUTPUT, "wb") as target:
        target.write(data)
    with open(OUTPUT.replace(".mufl", "-truncated.mufl"), "wb") as target:
        target.write(data[: len(data) * 2 // 3])
    print(f"Zapisano {len(data)} bajtów")
