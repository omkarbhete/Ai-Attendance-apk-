import os
import psycopg2
from psycopg2 import pool
import streamlit as st

# Database connection pool
db_pool = None

def get_db_pool():
    """Get or create database connection pool"""
    global db_pool
    if db_pool is None:
        db_pool = psycopg2.pool.SimpleConnectionPool(
            1, 20,
            host=os.getenv('DB_HOST'),
            port=os.getenv('DB_PORT', 5432),
            database=os.getenv('DB_NAME'),
            user=os.getenv('DB_USERNAME'),
            password=os.getenv('DB_PASSWORD'),
            sslmode='require'
        )
    return db_pool

def get_db_connection():
    """Get a connection from the pool"""
    pool = get_db_pool()
    return pool.getconn()

def release_db_connection(conn):
    """Release connection back to pool"""
    pool = get_db_pool()
    pool.putconn(conn)

@st.cache_resource
def get_cached_connection():
    """Get cached database connection for Streamlit"""
    return get_db_connection()

def execute_query(query, params=None, fetch=True):
    """Execute a database query with automatic connection management"""
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(query, params)
            if fetch:
                return cur.fetchall()
            conn.commit()
            return None
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        release_db_connection(conn)

# Made with Bob
