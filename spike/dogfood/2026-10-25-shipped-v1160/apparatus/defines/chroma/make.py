"""Seed and read a Chroma persistent directory with fixed embeddings (no model, no network).

    make.py seed <dir>     200 documents in one collection, then the odd half deleted
    make.py read <dir>     prints the collection's ids, documents and embeddings as one digest line
"""
import hashlib
import sys

import chromadb
from chromadb.config import Settings


def client(path):
    return chromadb.PersistentClient(path=path, settings=Settings(anonymized_telemetry=False))


def seed(path):
    c = client(path).get_or_create_collection("notes", embedding_function=None)
    ids = [f"n{i}" for i in range(200)]
    c.add(ids=ids, documents=[f"note {i}" for i in range(200)],
          embeddings=[[((i * 7 + j) % 13) / 13.0 for j in range(16)] for i in range(200)])
    c.delete(ids=[f"n{i}" for i in range(1, 200, 2)])


def read(path):
    c = client(path).get_collection("notes", embedding_function=None)
    got = c.get(include=["documents", "embeddings"])
    rows = sorted(zip(got["ids"], got["documents"], [[round(float(x), 6) for x in e] for e in got["embeddings"]]))
    print(len(rows), hashlib.sha256(repr(rows).encode()).hexdigest())


if __name__ == "__main__":
    {"seed": seed, "read": read}[sys.argv[1]](sys.argv[2])
