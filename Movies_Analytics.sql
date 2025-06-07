--1. Data Exploration:

--1.1. Count total no of rows
SELECT COUNT(*) FROM movies;

--1.2. Show the first five rows
SELECT * FROM movies LIMIT 5;

--1.3. List all columns with datatypes
SELECT
    column_name,
    data_type
FROM
    information_schema.columns
WHERE
    table_name = 'movies';
	
--1.4. Summary Statistics for numeric columns
SELECT
    COUNT(*) AS total_movies,
    AVG(budget) AS avg_budget,
    AVG(revenue) AS avg_revenue,
    AVG(runtime) AS avg_runtime,
    AVG(vote_average) AS avg_vote,
    MIN(release_date) AS earliest_release,
    MAX(release_date) AS latest_release
FROM movies;

--1.5. Show if there are any null values in selected columns
SELECT
    COUNT(*) FILTER (WHERE budget IS NULL) AS null_budget,
    COUNT(*) FILTER (WHERE revenue IS NULL) AS null_revenue,
    COUNT(*) FILTER (WHERE release_date IS NULL) AS null_release_date,
    COUNT(*) FILTER (WHERE genres IS NULL OR genres = '') AS null_or_empty_genres
FROM movies;

---2. Analysis and Insights

---2.1. TOP 10 Highest Rated Movies:
SELECT
    title,
    release_date,
    vote_average,
    vote_count
FROM
    movies
WHERE
    vote_count >= 50  -- filter out movies with too few votes but with high rating to avoid our results being skewed.
ORDER BY
    vote_average DESC,
    vote_count DESC
LIMIT 10;

---2.2. Which genre has the highest Avg. Budget? 
-- Ignore movies with zero budgets or missing values.
WITH genre_expanded AS (
  SELECT
    id,
    unnest(string_to_array(genres, ',')) AS genre,
    budget
  FROM movies
  WHERE budget > 0 AND genres IS NOT NULL
)
SELECT
  genre,
  ROUND(AVG(budget)) AS avg_budget
FROM genre_expanded
GROUP BY genre
ORDER BY avg_budget DESC;

---2.3. TOP 10 Movies with highest Avg. Budget?
SELECT
    title,
    release_date,
    budget
FROM movies
WHERE budget > 0
ORDER BY budget DESC
LIMIT 10;

---2.4. Median Budget for Movies released every year?
SELECT
  EXTRACT(YEAR FROM release_date) AS year,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY budget) AS median_budget
FROM movies
WHERE budget > 0 AND release_date IS NOT NULL
GROUP BY year
ORDER BY year;

---2.5. Which genre has the highest median revenue for each year?
WITH genre_year_expanded AS (
  SELECT
    unnest(string_to_array(genres, ',')) AS genre,
    EXTRACT(YEAR FROM release_date) AS release_year,
    revenue
  FROM movies
  WHERE release_date IS NOT NULL AND revenue > 0
),
genre_medians AS (
  SELECT
    genre,
    release_year,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY revenue) AS median_revenue
  FROM genre_year_expanded
  GROUP BY genre, release_year
)
SELECT gm1.release_year, gm1.genre, ROUND(gm1.median_revenue::numeric, 2) AS median_revenue
FROM genre_medians gm1
WHERE gm1.median_revenue = (
  SELECT MAX(gm2.median_revenue)
  FROM genre_medians gm2
  WHERE gm1.release_year = gm2.release_year
)
ORDER BY release_year;

---2.6. Which Movies were most profitable? Movies with best Revenue/Budget ratio?
SELECT
  title,
  budget,
  revenue,
  ROUND((((revenue - budget)::FLOAT / NULLIF(budget, 0)) * 100)::numeric, 2) AS profitability_percent
FROM movies
WHERE budget > 10000 AND revenue > 0 -- ignore tiny budgets
ORDER BY profitability_percent DESC
LIMIT 20;

---2.7. Which Movies were Proftiable each year?
WITH profitability_data AS (
  SELECT
    id,
    title,
    EXTRACT(YEAR FROM release_date) AS release_year,
    budget,
    revenue,
    ((revenue - budget)::FLOAT / NULLIF(budget, 0)) * 100 AS profitability_percent
  FROM movies
  WHERE release_date IS NOT NULL AND revenue > 0 AND budget > 10000
),
ranked_movies AS (
  SELECT *,
         RANK() OVER (PARTITION BY release_year ORDER BY profitability_percent DESC) AS rnk
  FROM profitability_data
)
SELECT
  release_year,
  title,
  ROUND(profitability_percent::numeric, 2) AS profitability_percent,
  budget,
  revenue
FROM ranked_movies
WHERE rnk = 1
ORDER BY release_year;

---2.8. Which Movies outperfomed their bugets?
WITH budget_revenue_ratio AS (
  SELECT
    title,
    budget,
    revenue,
    revenue::FLOAT / NULLIF(budget, 0) AS revenue_to_budget_ratio
  FROM movies
  WHERE budget > 0 AND revenue > 0
)
SELECT
  title,
  budget,
  revenue,
  ROUND(revenue_to_budget_ratio::numeric, 2) AS ratio
FROM budget_revenue_ratio
WHERE revenue_to_budget_ratio >= 5
ORDER BY ratio DESC;

---2.9. Which genres were most popular?
WITH genre_expanded AS (
  SELECT
    unnest(string_to_array(genres, ',')) AS genre,
    popularity
  FROM movies
  WHERE popularity IS NOT NULL
)
SELECT
  genre,
  ROUND(AVG(popularity)::numeric, 2) AS avg_popularity
FROM genre_expanded
GROUP BY genre
ORDER BY avg_popularity DESC
LIMIT 10;

---2.10. Which genres were both popular and profitable?
WITH genre_metrics AS (
  SELECT
    unnest(string_to_array(genres, ',')) AS genre,
    ((revenue - budget)::FLOAT / NULLIF(budget, 0)) * 100 AS profitability,
    popularity
  FROM movies
  WHERE revenue > 0 AND budget > 10000 AND popularity IS NOT NULL
)
SELECT
  genre,
  ROUND(AVG(popularity)::numeric, 2) AS avg_popularity,
  ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY profitability))::numeric, 2) AS median_profitability
FROM genre_metrics
GROUP BY genre
HAVING COUNT(*) > 10
ORDER BY avg_popularity DESC, median_profitability DESC
LIMIT 10;

---2.11. Which genres combinations are most common?
SELECT
  genres,
  COUNT(*) AS count
FROM movies
WHERE genres IS NOT NULL AND genres <> ''
GROUP BY genres
ORDER BY count DESC
LIMIT 10;

---2.12. Language distribution of Movies produced?
SELECT
  original_language,
  COUNT(*) AS movie_count
FROM movies
GROUP BY original_language
ORDER BY movie_count DESC
LIMIT 10;

---2.13. TOP 10 Movies with longest runtimes?
SELECT
  title,
  runtime
FROM movies
WHERE runtime IS NOT NULL
ORDER BY runtime DESC
LIMIT 10;

---2.14. Lets create budget groups and find out the relative performance of movies against their group.
WITH budget_band AS (
  SELECT *,
    CASE
      WHEN budget BETWEEN 0 AND 1_000_000 THEN 'Low Budget'
      WHEN budget BETWEEN 1_000_001 AND 10_000_000 THEN 'Mid Budget'
      WHEN budget BETWEEN 10_000_001 AND 50_000_000 THEN 'High Budget'
      WHEN budget > 50_000_000 THEN 'Blockbuster'
      ELSE 'Unknown'
    END AS budget_category
  FROM movies
  WHERE budget > 0 AND revenue > 0
),
band_averages AS (
  SELECT
    budget_category,
    ROUND(AVG(revenue)::numeric, 2) AS avg_revenue,
    COUNT(*) AS movie_count
  FROM budget_band
  GROUP BY budget_category
)
SELECT
  bb.title,
  bb.budget_category,
  bb.revenue,
  ba.avg_revenue,
  ROUND(((bb.revenue - ba.avg_revenue) / ba.avg_revenue) * 100, 2) AS performance_vs_category
FROM budget_band bb
JOIN band_averages ba ON bb.budget_category = ba.budget_category
ORDER BY performance_vs_category DESC
LIMIT 10;

---2.15. Lets calculate the no of movies released across years!
WITH yearly_counts AS (
  SELECT
    EXTRACT(YEAR FROM release_date) AS year,
    COUNT(*) AS movies_released
  FROM movies
  WHERE release_date IS NOT NULL
  GROUP BY year
)
SELECT
  year,
  movies_released,
  SUM(movies_released) OVER (ORDER BY year) AS cumulative_movies
FROM yearly_counts
ORDER BY year;