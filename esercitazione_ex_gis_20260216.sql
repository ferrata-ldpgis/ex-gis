--abilitazione estensione postgis
CREATE EXTENSION postgis;

--Crea una tabella users:
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL,
    posizione GEOMETRY(POINT, 3003)
);

--Crea una tabella listings con:
CREATE TABLE listings (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    titolo VARCHAR(255) NOT NULL,
    prezzo NUMERIC(10,2),
    posizione GEOMETRY(POINT, 3003),
    data_creazione DATE DEFAULT CURRENT_DATE,
    CONSTRAINT fk_user
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);

--Crea una tabella areas che rappresenti zone poligonali:
CREATE TABLE areas (
    id SERIAL PRIMARY KEY,
    nome_area TEXT NOT NULL,
    tipo_area TEXT,
    geometria GEOMETRY(POLYGON,3003)
);


--creazione indice users
CREATE INDEX idx_users_posizione_gist
ON users
USING GIST (posizione);

--creazione indice listings
CREATE INDEX idx_listings_posizione_gist
ON listings
USING GIST (posizione);

--creazione indice areas
CREATE INDEX idx_areas_posizione_gist
ON areas
USING GIST (geometria);


--inserisco 500 utenti casuali
INSERT INTO users (username, posizione)
SELECT
    'utente_' || gs || '@example.com',
     ST_SetSRID(ST_MakePoint(
           random() * (1600000 - 1200000) + 1200000,  -- X
           random() * (5200000 - 4600000) + 4600000   -- Y
       ), 3003)
FROM generate_series(1, 500) AS gs;

--inserisco 3000 annunci:
INSERT INTO listings (user_id, titolo, prezzo, posizione, data_di_creazione)
SELECT
    ((gs - 1) % 500) + 1 AS user_id,
    'titolo_' || gs,
    round((random() * 1000)::numeric, 2) AS prezzo,
    ST_SetSRID(
        ST_MakePoint(
            random() * (1600000 - 1200000) + 1200000,
            random() * (5200000 - 4600000) + 4600000
        ),
        3003
    ),
    CURRENT_DATE - (random() * 365)::int
FROM generate_series(1, 3000) AS gs;

--inserisco 30 aree poligonali
INSERT INTO areas (nome_area, tipo_area, geometria)
SELECT
    'Area ' || i,
    (ARRAY['quartiere', 'zona_consegna', 'comune'])[floor(random() * 3) + 1],
    ST_SetSRID(
        ST_MakePolygon(
            ST_MakeLine(ARRAY[
                ST_MakePoint(x, y),
                ST_MakePoint(x + 10000, y),
                ST_MakePoint(x + 10000, y + 10000),
                ST_MakePoint(x, y + 10000),
                ST_MakePoint(x, y)
            ])
        ),
        3003
    )
FROM (
    SELECT
        i,
        random() * (1600000 - 1200000) + 1200000 AS x,
        random() * (5200000 - 4600000) + 4600000 AS y
    FROM generate_series(1, 30) AS gs(i)
) t;

--faccio update delle posizioni degli annunci dell'utense con id 3
UPDATE listings SET posizione = (SELECT u.posizione FROM users as u JOIN listings as l ON u.id=l.user_id WHERE u.id=3 GROUP BY u.posizione) WHERE user_id=3;
--controllo
SELECT DISTINCT u.posizione, l.posizione FROM users as u JOIN listings as l ON u.id=l.user_id WHERE u.id=3;

--query:
--Trova tutti gli annunci entro 10 km dall’utente con ID = 3, ordinati per distanza crescente:
SELECT
    l.*,
    ST_AsText(l.posizione) AS point_listings
FROM listings l
JOIN users u ON u.id = 3
WHERE ST_DWithin(
    l.posizione,
    u.posizione,
    10000
)
ORDER BY ST_Distance(l.posizione, u.posizione) ASC;

--Trova tutti gli annunci contenuti nell’area con ID = 5
SELECT *
FROM listings
WHERE ST_Contains(
    (SELECT geometria FROM areas WHERE id = 5),
    posizione
);

--Restituisci tutti gli utenti appartenenti all’area con ID = 5
SELECT DISTINCT u.*,ST_AsText(u.posizione) AS point_users
FROM users u
JOIN areas a ON a.id = 5
WHERE ST_Contains(a.geometria, u.posizione);

--Restituisci tutti gli utenti con annunci all’interno di quell’area
SELECT DISTINCT u.*,l.posizione as listings_posizione, ST_AsText(u.posizione) AS point_users
FROM users u
JOIN listings l ON l.user_id = u.id
JOIN areas a ON a.id = 5
WHERE ST_Contains(a.geometria, l.posizione);


--Per ogni area, restituisci solo gli annunci con prezzo superiore alla media globale
SELECT l.*,
       (SELECT AVG(prezzo) FROM listings) as media_prezzo,
	   a.nome_area,
       ST_AsText(l.posizione) AS point_listings
FROM users as u
JOIN listings as l ON l.user_id = u.id
JOIN areas as a ON ST_Contains(a.geometria, l.posizione)
WHERE l.prezzo > (SELECT AVG(prezzo) FROM listings);


--Trova annunci entro 5 km dal confine di una certa area
SELECT l.*,
       ST_AsText(l.posizione) AS listing_point
FROM listings l
JOIN users u ON l.user_id = u.id
JOIN areas a ON a.id = 5
WHERE ST_DWithin(
    l.posizione,
    ST_Boundary(a.geometria), -- prende solo il bordo della geometria dell’area
    5000
);


--Trova gli annunci non contenuti nell’area 5
SELECT DISTINCT l.*,ST_AsText(l.posizione) AS point_listings
FROM listings l
JOIN areas a ON a.id = 5
WHERE NOT ST_Contains(a.geometria, l.posizione);


--Riscrivi una query di distanza usando:  prima un filtro spaziale grossolano (bounding box)
SELECT l.*, ST_AsText(l.posizione) AS point_listings
FROM listings l
WHERE posizione && ST_MakeEnvelope(1200000, 4600000, 1600000, 5200000, 3003)
AND ST_Within(posizione, ST_MakeEnvelope(1200000, 4600000, 1600000, 5200000, 3003));

--Riscrivi una query di distanza usando:  poi un filtro metrico preciso
SELECT
    l.*,
    ST_AsText(l.posizione) AS point_listings
FROM listings l
JOIN users u ON u.id = 3
WHERE ST_DWithin(
    l.posizione,
    u.posizione,
    10000
)
ORDER BY ST_Distance(l.posizione, u.posizione) ASC;


--Trova i 10 annunci più vicini a un utente dato, sfruttando l’indice spaziale:
SELECT *
FROM listings as l
ORDER BY  l.posizione <-> (SELECT posizione FROM users WHERE id=3)
LIMIT 10;


--Trova gli annunci che non ricadono in nessuna area.
SELECT l.*
FROM listings l
LEFT JOIN areas a
    ON ST_Contains(a.geometria, l.posizione)
WHERE a.id IS NULL;

--Individua le coppie di aree che si intersecano, evitando duplicati e auto-intersezioni.
SELECT a1.id AS area1_id,
       a2.id AS area2_id
FROM areas a1
JOIN areas a2
    ON a1.id < a2.id          -- evita auto-intersezioni e duplicati
WHERE ST_Intersects(a1.geometria, a2.geometria);

