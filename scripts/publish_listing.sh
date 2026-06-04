#!/usr/bin/env bash
#
# Publish the World Cup Prediction Pool as a Marketplace listing.
#
# NOTE: Marketplace listing creation cannot be fully automated via CLI.
# This script documents the manual steps required in Snowsight.
#
# Prerequisites:
#   - Application Package WORLDCUP_POOL_PKG exists with at least one version
#   - Container image pushed to Snowflake image repository
#   - Provider account has the ACCOUNTADMIN role or listing privileges

set -euo pipefail

echo "============================================================"
echo " World Cup 2026 Prediction Pool — Marketplace Listing Setup"
echo "============================================================"
echo ""
echo "Listing creation requires Snowsight UI. Follow these steps:"
echo ""
echo "1. OPEN SNOWSIGHT"
echo "   Navigate to: Data Products → Provider Studio"
echo ""
echo "2. CREATE LISTING"
echo "   Click '+ Listing'"
echo "   Select distribution:"
echo "     • 'Only Specified Consumers' — for internal org sharing"
echo "     • 'Anyone on Snowflake Marketplace' — for public listing"
echo ""
echo "3. LISTING DETAILS"
echo "   Title:       World Cup 2026 Prediction Pool"
echo "   Subtitle:    Run a company-wide World Cup prediction competition inside Snowflake"
echo "   Category:    Business Intelligence"
echo "   Pricing:     Free"
echo ""
echo "4. APP PACKAGE"
echo "   Select: WORLDCUP_POOL_PKG"
echo "   Release directive: default (latest version)"
echo ""
echo "5. DESCRIPTION"
echo "   Copy content from: app/readme.md"
echo "   (The Marketplace listing description supports markdown)"
echo ""
echo "6. SCREENSHOTS"
echo "   Upload from: docs/screenshots/"
echo "   Recommended:"
echo "     - Leaderboard view"
echo "     - Match predictions grid"
echo "     - Tournament bracket picker"
echo "     - Mobile responsive view"
echo ""
echo "7. CONSUMER REQUIREMENTS"
echo "   Note in description:"
echo "     - Enterprise Edition or higher"
echo "     - SPCS enabled"
echo "     - Grants: CREATE COMPUTE POOL, CREATE WAREHOUSE, BIND SERVICE ENDPOINT"
echo ""
echo "8. PUBLISH"
echo "   Review all sections, then click 'Publish'"
echo ""
echo "============================================================"
echo ""
echo "For org-internal listings, you can also set specific consumer"
echo "accounts after publishing:"
echo ""
echo "  ALTER LISTING <listing_name>"
echo "    SET ACCOUNTS = ('orgname.account1', 'orgname.account2');"
echo ""
echo "============================================================"
echo ""
echo "POST-PUBLISH VERIFICATION:"
echo ""

# Verify the package exists and has a version
echo "Checking application package status..."
snow sql -q "SHOW VERSIONS IN APPLICATION PACKAGE WORLDCUP_POOL_PKG;" --connection default 2>/dev/null || {
  echo "WARNING: Could not verify application package. Ensure WORLDCUP_POOL_PKG exists."
  echo "Run: ./scripts/create_version.sh"
}

echo ""
echo "Done. Complete the listing creation in Snowsight."
