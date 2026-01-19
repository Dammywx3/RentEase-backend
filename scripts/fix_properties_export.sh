#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/properties.ts"
[ -f "$FILE" ] || { echo "❌ $FILE not found"; exit 1; }

# If it already exports propertyRoutes, do nothing
if grep -q "export async function propertyRoutes" "$FILE"; then
  echo "✅ $FILE already exports propertyRoutes"
  exit 0
fi

# If it exports propertiesRoutes, rename it
if grep -q "export async function propertiesRoutes" "$FILE"; then
  perl -0777 -pi -e 's/export\s+async\s+function\s+propertiesRoutes\s*\(/export async function propertyRoutes(/g' "$FILE"
  echo "✅ Renamed propertiesRoutes -> propertyRoutes in $FILE"
  exit 0
fi

# If it exports something else, we add a wrapper export at the bottom
echo -e "\n// ✅ Export alias to match routes/index.ts\nexport const propertyRoutes = propertiesRoutes as any;\n" >> "$FILE"
echo "✅ Added propertyRoutes alias in $FILE (wrapper)"
