#!/usr/bin/env bash
# shellql/src/db_mock.sh — Mock SQLite adapter for UI development
#
# Source this file (instead of src/db.sh) when SHQL_MOCK=1.
# All functions return static fixture data so screens can be built and tested
# without a real database.

# ── Mock recent files ─────────────────────────────────────────────────────────

# Populate SHQL_RECENT_FILES with fixture paths for the welcome screen.
shql_mock_load_recent() {
    SHQL_RECENT_FILES=(
        "$HOME/projects/app.db"
        "$HOME/Downloads/chinook.sqlite"
        "$HOME/Documents/budget.db"
        "$HOME/work/analytics.db"
        "$HOME/scratch/test.sqlite"
    )
    SHQL_RECENT_NAMES=()
    SHQL_RECENT_DETAILS=()
    SHQL_RECENT_SOURCES=()
    SHQL_RECENT_REFS=()
    local _f _base _parent
    for _f in "${SHQL_RECENT_FILES[@]+"${SHQL_RECENT_FILES[@]}"}"; do
        _base="${_f##*/}"
        _parent="${_f%/*}"
        _parent="${_parent##*/}"
        SHQL_RECENT_NAMES+=("$_parent/$_base")
        SHQL_RECENT_DETAILS+=("$_f")
        SHQL_RECENT_SOURCES+=("local")
        SHQL_RECENT_REFS+=("$_f")   # mock has no UUIDs; path serves as ref
    done
}

# ── Mock adapter functions ────────────────────────────────────────────────────

# shql_db_list_tables <db_path>
shql_db_list_tables() {
    printf '%s\n' users orders products categories
}

# shql_db_list_objects <db_path>
# Print name TAB type (table or view).
shql_db_list_objects() {
    printf '%s\t%s\n' categories   table
    printf '%s\t%s\n' orders       table
    printf '%s\t%s\n' products     table
    printf '%s\t%s\n' users        table
    printf '%s\t%s\n' active_users view
}

# shql_db_describe <db_path> <table>
shql_db_describe() {
    local _table="${2:-users}"
    case "$_table" in
        users)
            printf '%s\n' \
                "CREATE TABLE users (" \
                "  id INTEGER PRIMARY KEY," \
                "  name TEXT NOT NULL," \
                "  email TEXT UNIQUE," \
                "  phone TEXT," \
                "  role TEXT DEFAULT 'member'," \
                "  status TEXT DEFAULT 'active'," \
                "  city TEXT," \
                "  country TEXT DEFAULT 'US'," \
                "  plan TEXT DEFAULT 'free'," \
                "  score INTEGER DEFAULT 0," \
                "  verified INTEGER DEFAULT 0," \
                "  last_login TEXT," \
                "  notes TEXT," \
                "  created_at TEXT DEFAULT CURRENT_TIMESTAMP," \
                "  updated_at TEXT" \
                ");"
            ;;
        orders)
            printf '%s\n' \
                "CREATE TABLE orders (" \
                "  id INTEGER PRIMARY KEY," \
                "  user_id INTEGER REFERENCES users(id)," \
                "  status TEXT DEFAULT 'pending'," \
                "  total REAL NOT NULL," \
                "  currency TEXT DEFAULT 'USD'," \
                "  shipping_address TEXT," \
                "  placed_at TEXT DEFAULT CURRENT_TIMESTAMP," \
                "  fulfilled_at TEXT" \
                ");"
            ;;
        products)
            printf '%s\n' \
                "CREATE TABLE products (" \
                "  id INTEGER PRIMARY KEY," \
                "  sku TEXT UNIQUE NOT NULL," \
                "  name TEXT NOT NULL," \
                "  description TEXT," \
                "  price REAL NOT NULL," \
                "  stock INTEGER DEFAULT 0," \
                "  category_id INTEGER REFERENCES categories(id)," \
                "  created_at TEXT DEFAULT CURRENT_TIMESTAMP" \
                ");"
            ;;
        categories)
            printf '%s\n' \
                "CREATE TABLE categories (" \
                "  id INTEGER PRIMARY KEY," \
                "  slug TEXT UNIQUE NOT NULL," \
                "  label TEXT NOT NULL," \
                "  parent_id INTEGER REFERENCES categories(id)" \
                ");"
            ;;
        *)
            printf 'CREATE TABLE %s (id INTEGER PRIMARY KEY);\n' "$_table"
            ;;
    esac
}

# shql_db_columns <db_path> <table>
# Returns TSV rows: name<TAB>type<TAB>flags  (flags: "PK", "NN", "PK NN", or "")
shql_db_columns() {
    local _table="${2:-users}"
    case "$_table" in
        users)
            printf 'id\tINTEGER\tPK\n'
            printf 'name\tTEXT\tNN\n'
            printf 'email\tTEXT\t\n'
            printf 'phone\tTEXT\t\n'
            printf 'role\tTEXT\t\n'
            printf 'status\tTEXT\t\n'
            ;;
        products)
            printf 'id\tINTEGER\tPK\n'
            printf 'sku\tTEXT\tNN\n'
            printf 'name\tTEXT\tNN\n'
            printf 'price\tREAL\tNN\n'
            printf 'stock\tINTEGER\t\n'
            ;;
        orders)
            printf 'id\tINTEGER\tPK\n'
            printf 'user_id\tINTEGER\t\n'
            printf 'status\tTEXT\t\n'
            printf 'total\tREAL\tNN\n'
            ;;
        *)
            printf 'id\tINTEGER\tPK\n'
            printf 'value\tTEXT\t\n'
            ;;
    esac
}

# shql_db_fetch <db_path> <table> [limit] [offset]
shql_db_fetch() {
    local _table="${2:-users}"
    case "$_table" in
        users)
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                id name email phone role status city country plan score verified last_login notes created_at updated_at
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                1  "Alice Nguyen"   "alice@example.com"   "555-0101" admin     active    "San Francisco" US pro    980 1 "2025-03-15" "Platform admin"     "2024-01-01" "2024-11-15"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                2  "Bob Okafor"     "bob@example.com"     "555-0102" member    active    "Austin"        US free   120 1 "2025-03-10" ""                   "2024-01-02" ""
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                3  "Charlie Rossi"  "charlie@example.com" "555-0103" member    active    "Chicago"       US pro    450 1 "2025-02-28" "Migrated from v1"   "2024-01-03" "2024-09-20"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                4  "Diana Park"     "diana@example.com"   "555-0104" member    inactive  "Seoul"         KR free     0 0 ""           "Deactivated by user" "2024-02-10" "2024-10-01"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                5  "Ethan Müller"   "ethan@example.com"   "555-0105" editor    active    "Berlin"        DE pro    760 1 "2025-03-14" ""                   "2024-02-14" ""
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                6  "Fatima Al-Amin" "fatima@example.com"  "555-0106" member    active    "Dubai"         AE team  310 1 "2025-03-12" ""                   "2024-03-01" "2024-12-01"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                7  "George Santos"  "george@example.com"  "555-0107" member    suspended "São Paulo"     BR free    55 1 "2024-11-30" "TOS violation"      "2024-03-15" "2024-11-30"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                8  "Hannah Schmidt" "hannah@example.com"  "555-0108" editor    active    "Vienna"        AT pro    880 1 "2025-03-16" ""                   "2024-04-02" ""
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                9  "Ivan Petrov"    "ivan@example.com"    "555-0109" member    active    "Moscow"        RU free   200 0 "2025-01-05" "Pending email verify" "2024-04-18" "2024-08-22"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                10 "Jess Tanaka"    "jess@example.com"    "555-0110" admin     active    "Tokyo"         JP team  995 1 "2025-03-16" "Regional admin"     "2024-05-05" "2025-01-10"
            ;;
        orders)
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                id user_id status total currency shipping_address placed_at fulfilled_at
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                1 1 fulfilled 49.99  USD "123 Main St, San Francisco, CA" "2024-06-01" "2024-06-03"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                2 2 pending   12.50  USD "456 Oak Ave, Austin, TX"        "2024-06-15" ""
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                3 1 fulfilled 199.00 USD "123 Main St, San Francisco, CA" "2024-07-01" "2024-07-04"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                4 4 cancelled 34.00  KRW "77 Gangnam-daero, Seoul"        "2024-07-20" ""
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                5 3 shipped   89.95  USD "900 N Michigan Ave, Chicago, IL" "2024-08-05" ""
            ;;
        products)
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                id sku name description price stock category_id created_at
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                1 "WDG-001" "Widget Pro"    "Heavy-duty widget"      9.99  142 1 "2024-01-05"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                2 "WDG-002" "Widget Lite"   "Lightweight widget"     4.99  380 1 "2024-01-05"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                3 "GDG-001" "Gadget X"      "Next-gen gadget"       24.99   57 2 "2024-02-10"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                4 "GDG-002" "Gadget Y"      "Budget gadget"         14.99  210 2 "2024-02-10"
            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                5 "ACC-001" "Carry Case"    "Universal carry case"   7.50  500 3 "2024-03-01"
            ;;
        categories)
            printf '%s\t%s\t%s\t%s\n' id slug label parent_id
            printf '%s\t%s\t%s\t%s\n' 1 widgets   "Widgets"     ""
            printf '%s\t%s\t%s\t%s\n' 2 gadgets   "Gadgets"     ""
            printf '%s\t%s\t%s\t%s\n' 3 accessories "Accessories" ""
            ;;
        *)
            printf '%s\t%s\n' id value
            printf '%s\t%s\n' 1 "mock row"
            ;;
    esac
}

# shql_db_columns <db_path> <table>
# Print column info as TSV rows: name TAB type TAB flags (no header).
shql_db_columns() {
    local _table="${2:-users}"
    case "$_table" in
        users)
            printf '%s\t%s\t%s\n' id         INTEGER  PK
            printf '%s\t%s\t%s\n' name        TEXT     NN
            printf '%s\t%s\t%s\n' email       TEXT     ''
            printf '%s\t%s\t%s\n' phone       TEXT     ''
            printf '%s\t%s\t%s\n' role        TEXT     ''
            printf '%s\t%s\t%s\n' status      TEXT     ''
            printf '%s\t%s\t%s\n' city        TEXT     ''
            printf '%s\t%s\t%s\n' country     TEXT     ''
            printf '%s\t%s\t%s\n' plan        TEXT     ''
            printf '%s\t%s\t%s\n' score       INTEGER  ''
            printf '%s\t%s\t%s\n' verified    INTEGER  ''
            printf '%s\t%s\t%s\n' last_login  TEXT     ''
            printf '%s\t%s\t%s\n' notes       TEXT     ''
            printf '%s\t%s\t%s\n' created_at  TEXT     ''
            printf '%s\t%s\t%s\n' updated_at  TEXT     ''
            ;;
        orders)
            printf '%s\t%s\t%s\n' id               INTEGER 'PK'
            printf '%s\t%s\t%s\n' user_id          INTEGER ''
            printf '%s\t%s\t%s\n' status           TEXT    ''
            printf '%s\t%s\t%s\n' total            REAL    'NN'
            printf '%s\t%s\t%s\n' currency         TEXT    ''
            printf '%s\t%s\t%s\n' shipping_address TEXT    ''
            printf '%s\t%s\t%s\n' placed_at        TEXT    ''
            printf '%s\t%s\t%s\n' fulfilled_at     TEXT    ''
            ;;
        products)
            printf '%s\t%s\t%s\n' id          INTEGER 'PK'
            printf '%s\t%s\t%s\n' sku         TEXT    'NN'
            printf '%s\t%s\t%s\n' name        TEXT    'NN'
            printf '%s\t%s\t%s\n' description TEXT    ''
            printf '%s\t%s\t%s\n' price       REAL    'NN'
            printf '%s\t%s\t%s\n' stock       INTEGER ''
            printf '%s\t%s\t%s\n' category_id INTEGER ''
            printf '%s\t%s\t%s\n' created_at  TEXT    ''
            ;;
        categories)
            printf '%s\t%s\t%s\n' id        INTEGER 'PK'
            printf '%s\t%s\t%s\n' slug      TEXT    'NN'
            printf '%s\t%s\t%s\n' label     TEXT    'NN'
            printf '%s\t%s\t%s\n' parent_id INTEGER ''
            ;;
        *)
            printf '%s\t%s\t%s\n' id INTEGER 'PK'
            ;;
    esac
}

# shql_db_query <db_path> <sql>
# First line: tab-separated column headers. Subsequent lines: data rows.
shql_db_query() {
    printf 'id\tname\temail\n'
    printf '1\tAlice\talice@example.com\n'
    printf '2\tBob\tbob@example.com\n'
    printf '3\tCarol\tcarol@example.com\n'
}
