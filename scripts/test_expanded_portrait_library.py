"""Regression gates: stale approval and changed crop geometry cannot publish art."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image, ImageDraw
import expanded_portrait_library as packager
from portrait_library import digest


class ExpandedPortraitGateTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.library = self.root/'assets/portraits-v4'
        (self.library/'source').mkdir(parents=True)
        image=Image.new('RGB',(1024,1024))
        draw=ImageDraw.Draw(image)
        for cell in range(16):
            row,col=divmod(cell,4)
            draw.rectangle((col*256,row*256,(col+1)*256-1,(row+1)*256-1),fill=(cell*15,80,120))
        self.source=self.library/'source/batch_24.png'
        image.save(self.source)
        self.write(self.library/'prompts.json',{'batches':[{'batch':24,'firstId':378,'group':'civilian','rowAges':[22,32,47,62],'prompt':'fixture'}]})
        self.write(self.library/'prompt-overrides.json',{})
        self.write(self.library/'crop-overrides.json',{})
        for old in ('v2','v3'):
            self.write(self.root/f'assets/portraits-{old}/manifest.json',{'portraits':[]})
        self.approvals=self.root/'approval.json'
        self.approval={'sourceSha256':digest(self.source.read_bytes()),'status':'passed',
                       'castingSha256':packager.casting_hash({'batch':24,'firstId':378,'group':'civilian','rowAges':[22,32,47,62]}),
                       'columnEdges':[0,256,512,768,1024],'rowEdges':[0,256,512,768,1024]}
        self.write(self.approvals,{'24':self.approval})
        self.patch=patch.object(packager,'ROOT',self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def write(self,path,value):
        path.parent.mkdir(parents=True,exist_ok=True)
        path.write_text(json.dumps(value),encoding='utf-8')

    def test_hash_and_geometry_bound_review_accepts_only_reviewed_source(self):
        result=packager.build(partial=True,approvals=self.approvals)
        self.assertEqual(result['unapproved'],[])
        self.assertFalse((self.root/'upstream/assets/modern/portraits_v2').exists())
        self.approval['sourceSha256']='0'*64
        self.write(self.approvals,{'24':self.approval})
        self.assertEqual(packager.build(partial=True,approvals=self.approvals)['unapproved'],[24])

    def test_changed_mapping_invalidates_approval(self):
        self.write(self.library/'crop-overrides.json',{'24':{'rowEdges':[0,250,512,768,1024]}})
        self.assertEqual(packager.build(partial=True,approvals=self.approvals)['unapproved'],[24])

    def test_changed_casting_metadata_cannot_reuse_source_approval(self):
        path=self.library/'prompts.json'
        brief=json.loads(path.read_text())
        brief['batches'][0]['rowAges']=[72,82,92,100]
        self.write(path,brief)
        self.assertEqual(packager.build(partial=True,approvals=self.approvals)['unapproved'],[24])

    def test_recorded_review_supports_clean_checkout_regeneration(self):
        record=dict(self.approval,batch=24,sourceReview='passed')
        self.write(self.library/'manifest.json',{'atlases':[record]})
        self.assertEqual(packager.build(partial=True)['unapproved'],[])
        record['castingSha256']='0'*64
        self.write(self.library/'manifest.json',{'atlases':[record]})
        self.assertEqual(packager.build(partial=True)['unapproved'],[24])

    def test_missing_review_or_incomplete_batch_cannot_write_runtime(self):
        with self.assertRaisesRegex(ValueError,'Publish blocked'):
            packager.build(approvals=self.approvals)
        self.assertFalse((self.root/'upstream').exists())
        self.assertEqual(packager.build(partial=True)['unapproved'],[24])

    def test_bad_geometry_and_duplicate_faces_are_rejected(self):
        self.write(self.library/'crop-overrides.json',{'24':{'rowEdges':[0,512,256,768,1024]}})
        with self.assertRaisesRegex(ValueError,'invalid source crop boundaries'):
            packager.build(partial=True)
        self.write(self.library/'crop-overrides.json',{})
        Image.new('RGB',(1024,1024),'white').save(self.source)
        with self.assertRaisesRegex(ValueError,'Duplicate portrait crop'):
            packager.build(partial=True)


if __name__=='__main__': unittest.main()
