"""Write the reproducible 1,024-identity ImageGen expansion brief (no API calls)."""
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STYLE = ('Use case: stylized-concept. ONE SQUARE game portrait atlas, EXACTLY SIXTEEN distinct fictional subjects in a perfectly aligned 4 columns x 4 rows grid. Equal square cells edge-to-edge; NO gutters, borders, grid lines, labels, text or watermark. Restrained realistic hand-painted gouache and fine ink, warm ivory textured parchment background, muted olive charcoal brown dull burgundy, soft even lighting. CRITICAL FRAMING: mid chest up, camera pulled back, entire outer hair silhouette and ears INSIDE its own cell with clear parchment headroom at least 8% of cell height above crown; chin around 62% down each cell. No clipped heads at any row boundary. Consistent scale, plausible individual anatomy, natural neutral expressions. No props, weapons, logos, caricature or glamour. ')
ANCESTRIES = ['Black', 'East Asian', 'white', 'South Asian', 'Latino', 'Middle Eastern', 'Southeast Asian', 'Indigenous American', 'mixed Black and white', 'Pacific Islander', 'North African', 'mixed Asian and Latino']
HAIR_F = ['short coils', 'straight chin-length bob', 'wavy pixie', 'loose braid', 'short natural curls', 'tied-back locs', 'cropped side-part', 'low ponytail', 'shoulder-length waves', 'tight bun', 'close-cropped hair', 'swept-back curls']
HAIR_M = ['short curls', 'straight side-part', 'close-cropped hair', 'wavy fringe', 'shaved head', 'short coiled hair', 'receding temples', 'cropped waves', 'short beard and swept hair', 'neat moustache and short hair', 'curly crop', 'bald head and stubble']
SHAPES = ['broad square face', 'long narrow face', 'round face', 'angular cheekbones', 'soft oval face', 'wide cheekbones', 'narrow chin', 'prominent rounded nose']
CLOTHES = {'civilian':'plain casual shirts, knitwear and lightweight jackets', 'professional':'plain office blouses, collars and jackets', 'trades':'practical canvas work jackets, cotton shirts, no tools', 'academic':'cardigans, tweed jackets and plain medical coats without props', 'creative':'individual casual layered clothing, scarves, no props', 'security':'plain dark uniform collars without badges, helmets or insignia', 'religious':'varied modest clerical collars, robes and religious head coverings, no readable symbols', 'punk':'muted punk clothes, modest piercings and short colourful hair', 'goth':'restrained gothic clothes and dark hairstyles', 'emo':'subtle emo clothes and swept fringes', 'biker':'plain leather jackets, no logos', 'elderly':'comfortable ordinary knitwear and collared shirts', 'child':'age-appropriate everyday shirts, sweaters and fully covered modest clothing', 'teenager':'age-appropriate ordinary shirts and light jackets, fully clothed', 'mutant':'ordinary clothing, subtle fictional non-gory mutations such as unusual skin tones and asymmetric brows'}

def main():
    groups = [g for g in ['civilian','professional','trades','academic','creative'] for _ in range(8)]
    groups += ['punk','goth','emo','biker','religious','religious','security','security','professional','professional','creative','creative']
    groups += ['child']*3 + ['teenager']*3 + ['elderly']*4 + ['mutant','canine']
    batches=[]
    for offset, group in enumerate(groups):
        batch=24+offset
        ages = ([22,32,47,62] if offset%3==0 else [25,38,53,68] if offset%3==1 else [28,44,59,73])
        if group=='child': ages=[4,7,10,12]
        if group=='teenager': ages=[14,16,18,19]
        if group=='elderly': ages=[76,82,88,95]
        if group=='canine': ages=[0]*4
        rng=random.Random(104729+batch)
        descriptions=[]
        for row in range(4):
            people=[]
            for col in range(4):
                if group=='canine':
                    breeds=['German shepherd','Labrador','Doberman','Rottweiler','Belgian shepherd','Boxer','mixed shepherd','black retriever','brown mastiff','white shepherd','terrier mix','brindle mastiff','golden retriever','grey shepherd','black-and-tan hound','collie mix']
                    desc=breeds[row*4+col]+' dog, distinct coat and muzzle, head and upper chest, all ears fully inside cell'
                else:
                    gender=('girl' if col%2==0 else 'boy') if group=='child' else ('woman' if col%2==0 else 'man')
                    if group=='teenager' and ages[row]<18: gender='girl' if col%2==0 else 'boy'
                    hair=rng.choice(HAIR_F if col%2==0 else HAIR_M)
                    if group in ('child','teenager'): hair=hair.replace('short beard and swept hair','swept hair').replace('neat moustache and short hair','short hair').replace('receding temples','short hair').replace('bald head and stubble','short straight hair')
                    desc=f'{rng.choice(ANCESTRIES)} {gender}, age {ages[row]}, {hair}, {rng.choice(SHAPES)}'
                    if ages[row]>=60: desc+=', naturally grey or silver hair and age-appropriate skin'
                people.append(desc)
            descriptions.append(f'Row {row+1}: '+'; '.join(people)+'.')
        prompt=STYLE+('Sixteen distinct dogs, no human bodies. ' if group=='canine' else 'EACH ROW alternates female/male/female/male presentation. Clothing: '+CLOTHES[group]+'. ')+ ' '.join(descriptions)
        if batch>=66:
            prompt+=' Identity uniqueness is critical: all sixteen are unrelated people with clearly different eye spacing, nose bridge and width, lip shapes, chin and jaw proportions, builds, ears and brow structure. Never show the same face aged into a later row; different hairstyle alone is insufficient. No idealized repeated facial template.'
        category='ordinary' if offset<40 else 'professionSubculture' if offset<52 else 'childTeen' if offset<58 else 'elderly' if offset<62 else 'mutantNonhuman'
        batches.append({'batch':batch,'firstId':378+offset*16,'group':group,'category':category,'rowAges':ages,'prompt':prompt})
    output=ROOT/'assets/portraits-v4/prompts.json'
    if output.exists():
        raise ValueError('Refusing to overwrite recorded generation prompts; edit the existing brief deliberately or choose a new library.')
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps({'version':4,'generator':'built-in image_gen','targetPortraitCount':1024,'firstId':378,'lastId':1401,'batches':batches},indent=2)+'\n',encoding='utf-8')

if __name__=='__main__': main()
