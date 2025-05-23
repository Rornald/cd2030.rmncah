#' Calculate Outliers Summary by Year
#'
#' `calculate_outliers_summary` provides an annual overview of data quality by
#' summarizing extreme outliers for health indicators. Outliers are identified
#' based on robust statistical metrics (Median Absolute Deviation, MAD) and
#' flagged when they deviate significantly (beyond five MADs from the median).
#'
#' @param .data A data frame with district-level health indicators. This data
#'   frame must include a `district` and `year` column, along with indicator columns
#'   for calculating outliers. Outlier flags should be computed prior and named
#'   with the suffix `_outlier5std` (e.g., `anc1_outlier5std` where 1 indicates an
#'   outlier and 0 indicates non-outliers).
#' @param admin_level Character. The administrative level at which to calculate
#'   reporting rates. Must be one of `'national'`, `'adminlevel_1'` or `'district'`.
#'
#' @details
#' - **Outlier Detection**: Outliers are calculated based on Hampel’s robust X84
#'   method, using the Median Absolute Deviation (MAD). This method identifies values
#'   that exceed five times the MAD from the median, reducing the influence of extreme
#'   values on the analysis.
#' - **Annual Non-Outlier Rate**: For each indicator and each year, the function calculates the
#'   percentage of non-outliers. Additionally, the function aggregates the non-outlier
#'   rates across all indicators, as well as vaccination-only and tracer-only indicators,
#'   providing an overall data quality summary.
#'
#' @return
#' A `cd_outliers_summary` object (tibble) with:
#'   - Each indicator's non-outlier percentage (`_outlier5std` columns).
#'   - Overall non-outlier summaries across all indicators, vaccination indicators, and tracers.
#'
#' @examples
#' \dontrun{
#' # Check for extreme outliers in indicator data
#' calculate_outliers_summary(data)
#' }
#'
#' @export
calculate_outliers_summary <- function(.data, admin_level = c('national', 'adminlevel_1', 'district')) {
  year <- . <- NULL

  check_cd_data(.data)
  admin_level <- arg_match(admin_level)
  admin_level_cols <- get_admin_columns(admin_level)

  allindicators <- get_all_indicators()
  ipd_indicators <- get_indicator_groups()['ipd']
  four_indicator <- paste0(allindicators[which(!allindicators %in% ipd_indicators)], '_outlier5std')

  data <- .data %>%
    calculate_outlier_core(indicators = allindicators, admin_level = admin_level) %>%
    summarise(
      across(ends_with('_outlier5std'), mean, na.rm = TRUE),
      .by =c(admin_level_cols, 'year')
    ) %>%
    mutate(
      mean_out_all = rowMeans(select(., ends_with('_outlier5std')), na.rm = TRUE),
      mean_out_four = rowMeans(select(., any_of(four_indicator)), na.rm = TRUE),
      across(c(ends_with('_outlier5std'), starts_with('mean_out_')), ~ round((1 - .x) * 100, 0))
    )

  new_tibble(
    data,
    class = 'cd_outlier',
    admin_level = admin_level
  )
}

#' Calculate District-Level Outliers Summary by Year
#'
#' `calculate_district_outlier_summary` computes a district-level summary of extreme
#' outliers for specified health indicators. This function aggregates extreme outlier counts
#' for each indicator by first identifying the maximum outlier flag within each district
#' and year. An outlier is flagged based on Hampel's X84 method, where values exceeding
#' five Median Absolute Deviations (MAD) from the median are considered extreme outliers.
#'
#' @param .data A data frame containing district-level health indicator data. This data
#'   frame must include precomputed outlier flags (columns ending in `_outlier5std`),
#'   where 1 represents an outlier and 0 represents non-outliers.
#'
#' @details
#' - **Outlier Aggregation**: The function first calculates the maximum outlier flag within
#'   each district and year. This district-level flag is used to determine if extreme outliers
#'   are present for each indicator.
#' - **Non-Outlier Percentage**: After aggregating by district and year, it computes the
#'   mean percentage of districts without extreme outliers for each indicator, as well as
#'   overall summaries for vaccination-only and tracer indicators.
#' - **Rounding**: Non-outlier percentages are rounded to two decimal places for clarity
#'   in reporting and analysis.
#'
#' @return A `cd_district_outliers_summary` object (tibble) with:
#'   - Each indicator's percentage of districts without extreme outliers, calculated yearly.
#'   - Aggregated summaries for non-outliers across all indicators, vaccination indicators,
#'     and tracer indicators.
#'
#' @examples
#' \dontrun{
#' # Summarize the proportion of districts without extreme outliers
#' calculate_district_outlier_summary(data)
#' }
#'
#' @export
calculate_district_outlier_summary <- function(.data) {
  district <- year <- . <- NULL

  check_cd_data(.data)

  allindicators <- get_all_indicators()
  ipd_indicators <- get_indicator_groups()['ipd']
  four_indicator <- paste0(allindicators[which(!allindicators %in% ipd_indicators)], '_outlier5std')

  data <- .data %>%
    calculate_outlier_core(indicators = allindicators, admin_level = 'district') %>%
    summarise(
      across(ends_with('_outlier5std'), ~ robust_max(.)),
      .by = c(district, year)
    ) %>%
    summarise(across(ends_with('_outlier5std'), mean, na.rm = TRUE), .by = year) %>%
    mutate(
      mean_out_all = rowMeans(select(., ends_with('_outlier5std')), na.rm = TRUE),
      mean_out_four = rowMeans(select(., any_of(four_indicator)), na.rm = TRUE),
      across(c(ends_with('_outlier5std'), starts_with('mean_out_')), ~ round((1 - .x) * 100, 2))
    )

  new_tibble(
    data,
    class = 'cd_district_outliers_summary'
  )
}

#' Identify Outlier Units by Month for a Given Indicator
#'
#' This function summarizes a single immunization indicator by month and administrative level,
#' then applies a Hampel filter (5 × MAD) to flag extreme outliers. It returns a tidy object
#' suitable for plotting or time-series review at subnational levels.
#'
#' @param .data A `cd_data` object containing monthly health indicator data.
#' @param indicator Character. The name of a single indicator to evaluate for outliers.
#' @param admin_level Character. The administrative level to summarize by.
#'   Options are `'adminlevel_1'` or `'district'`.
#'
#' @details
#' - Computes monthly means of the specified indicator by administrative unit and time.
#' - Calculates median and MAD (Median Absolute Deviation) for outlier detection.
#' - Flags outliers when values exceed ±5×MAD from the median.
#'
#' @return A `cd_outlier_list` object (a tibble) with the following columns:
#'   - Grouping columns (`adminlevel_1`, `district`, `year`, `month`)
#'   - The selected indicator
#'   - Median (`<indicator>_med`)
#'   - MAD (`<indicator>_mad`)
#'   - Outlier flag (`<indicator>_outlier5std`)
#'
#' @examples
#' \dontrun{
#' # Detect monthly outliers in Penta1 at district level
#' outliers <- list_outlier_units(cd_data, indicator = 'penta1', admin_level = 'district')
#'
#' # Plot flagged points in a specific region
#' plot(outliers, region = 'Nakuru')
#' }
#'
#' @export
list_outlier_units <- function(.data,
                               indicator,
                               admin_level = c('adminlevel_1', 'district')) {
  check_cd_data(.data)
  indicator <- arg_match(indicator, get_all_indicators())
  admin_level <- arg_match(admin_level)

  admin_level_cols <- get_admin_columns(admin_level)
  admin_level_cols <- c(admin_level_cols, 'year', 'month')

  x <- .data %>%
    calculate_outlier_core(indicators = indicator, admin_level = admin_level) %>%
    select(any_of(c(admin_level_cols, indicator, paste0(indicator, c('_med', '_mad', '_outlier5std')))))

  new_tibble(
    x,
    class = 'cd_outlier_list',
    indicator = indicator,
    admin_level = admin_level
  )
}


#' Core Function to Calculate Outlier Metrics
#'
#' @param .data A `cd_data` object.
#' @param indicators A character vector of indicators.
#' @param admin_level Administrative level: 'national', 'adminlevel_1', or 'district'.
#'
#' @return A tibble with outlier metrics.
#'
#' @noRd
calculate_outlier_core <- function(.data, indicators, admin_level = c('national', 'adminlevel_1', 'district')) {
  check_cd_data(.data)
  check_required(indicators)

  admin_level <- arg_match(admin_level)
  group_vars <- get_admin_columns(admin_level)

  .data %>%
    summarise(across(any_of(indicators), mean, na.rm = TRUE), .by = c(group_vars, 'year', 'month')) %>%
    add_outlier5std_column(indicators = indicators, group_by = group_vars)
}
