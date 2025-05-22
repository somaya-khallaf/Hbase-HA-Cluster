import happybase
import hashlib
import random
from datetime import datetime, timedelta
from faker import Faker
import json

# Initialize Faker and HBase connection
fake = Faker()

try:
    connection = happybase.Connection('hmaster1', port=9090)
    connection.open()
except Exception as e:
    print(f"Failed to connect to HBase: {e}")
    exit(1)

# Create table if it doesn't exist
table_name = 'web_pages'
if table_name.encode() not in connection.tables():
    print(f"Creating table {table_name}...")
    connection.create_table(
        table_name,
        {
            'content': dict(),  # For HTML content
            'metadata': dict(),  # For JSON metadata
            'outlinks': dict(),  # For JSON outlinks
            'inlinks': dict()    # For JSON inlinks
        }
    )

table = connection.table(table_name)

# Constants
DOMAINS = ['example.com', 'test.org', 'demo.net', 'sample.io', 'web.dev']
CONTENT_SIZES = {'small': 100, 'medium': 300, 'large': 600}
NUM_PAGES = 20
NUM_SALT_BUCKETS = 10

def generate_url(domain, i):
    return f"https://{domain}/page{i}"

def get_salt(domain, timestamp):
    """Generate a salt bucket number from 0 to 9."""
    key = f"{domain}{timestamp}"
    return int(hashlib.md5(key.encode()).hexdigest(), 16) % NUM_SALT_BUCKETS

def create_row_key(domain, timestamp, url):
    """Create salted row key."""
    salt = get_salt(domain, timestamp)
    url_hash = hashlib.md5(url.encode()).hexdigest()[:8]
    return f"{salt}|{domain}|{timestamp}|{url_hash}"

def generate_html(title, word_count):
    """Generate simple HTML with the specified number of words."""
    text = fake.text(max_nb_chars=word_count * 5)
    return f"<html><head><title>{title}</title></head><body><p>{text}</p></body></html>"

def generate_page(i):
    """Generate one page's data."""
    domain = random.choice(DOMAINS)
    url = generate_url(domain, i)
    size_category = random.choice(list(CONTENT_SIZES.keys()))
    word_count = CONTENT_SIZES[size_category]
    days_ago = random.randint(0, 180)
    timestamp = int((datetime.now() - timedelta(days=days_ago)).timestamp())

    title = fake.sentence()
    html = generate_html(title, word_count)
    metadata = {
        'title': title,
        'status_code': random.choice([200, 404, 500]),
        'last_modified': datetime.fromtimestamp(timestamp).isoformat(),
        'size': size_category
    }

    row_key = create_row_key(domain, timestamp, url)

    return {
        'row_key': row_key,
        'url': url,
        'html': html,
        'metadata': metadata,
        'size_category': size_category,
        'domain': domain,
        'timestamp': timestamp
    }

def generate_pages(n):
    """Generate n web pages."""
    return [generate_page(i) for i in range(n)]

def generate_links(pages):
    """Assign 2 outlinks to each page and update inlinks in linked pages."""
    urls = [page['url'] for page in pages]
    for page in pages:
        outlinks = random.sample([u for u in urls if u != page['url']], k=2)
        page['outlinks'] = outlinks
        for target_url in outlinks:
            target_page = next(p for p in pages if p['url'] == target_url)
            target_page.setdefault('inlinks', []).append(page['url'])

def insert_page(page):
    """Insert one page into HBase."""
    data = {
        b'content:html': page['html'].encode(),
        b'metadata:json': json.dumps(page['metadata']).encode(),
        b'outlinks:json': json.dumps(page.get('outlinks', [])).encode(),
        b'inlinks:json': json.dumps(page.get('inlinks', [])).encode()
    }
    table.put(page['row_key'], data)

def insert_all_pages(pages):
    """Insert all pages into HBase."""
    for page in pages:
        insert_page(page)

def main():
    pages = generate_pages(NUM_PAGES)
    generate_links(pages)
    insert_all_pages(pages)
if __name__ == "__main__":
    main()
