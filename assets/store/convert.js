const fs = require('fs');
const { execSync } = require('child_process');

// Check if sharp is available, if not use alternative method
async function convertWithSharp() {
  const sharp = require('sharp');

  // Convert icon to multiple sizes
  const iconSizes = [512, 1024];
  for (const size of iconSizes) {
    await sharp('icon.svg')
      .resize(size, size)
      .png()
      .toFile(`icon_${size}x${size}.png`);
    console.log(`Created: icon_${size}x${size}.png`);
  }

  // Convert feature graphic
  await sharp('feature_graphic.svg')
    .resize(1024, 500)
    .png()
    .toFile('feature_graphic_1024x500.png');
  console.log('Created: feature_graphic_1024x500.png');
}

// Alternative: Use resvg-js which has better SVG support
async function convertWithResvg() {
  const { Resvg } = require('@aspect-dev/resvg-js');

  // Icon sizes
  const iconSvg = fs.readFileSync('icon.svg', 'utf8');
  for (const size of [512, 1024]) {
    const resvg = new Resvg(iconSvg, {
      fitTo: { mode: 'width', value: size }
    });
    const pngData = resvg.render();
    fs.writeFileSync(`icon_${size}x${size}.png`, pngData.asPng());
    console.log(`Created: icon_${size}x${size}.png`);
  }

  // Feature graphic
  const featureSvg = fs.readFileSync('feature_graphic.svg', 'utf8');
  const resvg = new Resvg(featureSvg, {
    fitTo: { mode: 'width', value: 1024 }
  });
  const pngData = resvg.render();
  fs.writeFileSync('feature_graphic_1024x500.png', pngData.asPng());
  console.log('Created: feature_graphic_1024x500.png');
}

// Try sharp first, then resvg
async function main() {
  try {
    await convertWithSharp();
  } catch (e) {
    console.log('sharp not available, trying @aspect-dev/resvg-js...');
    try {
      await convertWithResvg();
    } catch (e2) {
      console.error('Please install: npm install sharp or npm install @aspect-dev/resvg-js');
      process.exit(1);
    }
  }
}

main();
