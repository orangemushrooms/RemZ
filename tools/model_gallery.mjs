import sharp from 'sharp';
import fs from 'node:fs';
const specs=JSON.parse(fs.readFileSync('tools/missing_assets.json','utf8'));
const tiles=[];
let i=0;
for(const name of Object.keys(specs)){
  const x=(i%4)*512,y=Math.floor(i/4)*412;
  tiles.push({input:await sharp(`artifacts/model-audit/${name}.png`).resize(512,384).toBuffer(),left:x,top:y});
  const label=Buffer.from(`<svg width="512" height="28"><rect width="512" height="28" fill="#18212b"/><text x="12" y="19" fill="#e2e8f0" font-family="Arial" font-size="15">${name}</text></svg>`);
  tiles.push({input:label,left:x,top:y+384});i++;
}
await sharp({create:{width:2048,height:Math.ceil(i/4)*412,channels:3,background:'#101820'}}).composite(tiles).png().toFile('artifacts/model-audit/gallery.png');
console.log('artifacts/model-audit/gallery.png');
