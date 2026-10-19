"""`grant_admin.py` 的純函式測試。不連網、不需要任何憑證。

    python3 tools/test_grant_admin.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import grant_admin as g  # noqa: E402


class ParseScopes(unittest.TestCase):
    def test_編號(self):
        self.assertEqual(g.parse_scopes('1,2'), (['contentReview', 'productManage'], None))
        self.assertEqual(g.parse_scopes('3'), (['platformConfig'], None))

    def test_空白或全形分隔(self):
        self.assertEqual(g.parse_scopes('1 3')[0], ['contentReview', 'platformConfig'])
        self.assertEqual(g.parse_scopes('1、2，3')[0], g.SCOPE_KEYS)

    def test_中文與英文名稱(self):
        self.assertEqual(g.parse_scopes('內容審核')[0], ['contentReview'])
        self.assertEqual(g.parse_scopes('productManage')[0], ['productManage'])

    def test_全部(self):
        for t in ('全部', 'all', 'ALL', 'a'):
            self.assertEqual(g.parse_scopes(t)[0], g.SCOPE_KEYS, t)

    def test_重複只算一次(self):
        self.assertEqual(g.parse_scopes('1,1,1')[0], ['contentReview'])

    def test_空白不給預設值(self):
        for t in ('', '   ', None, ',,'):
            self.assertIsNone(g.parse_scopes(t)[0], repr(t))
            self.assertIsNotNone(g.parse_scopes(t)[1], repr(t))

    def test_不認得的輸入(self):
        self.assertIsNone(g.parse_scopes('9')[0])
        self.assertIsNone(g.parse_scopes('0')[0])
        self.assertIsNone(g.parse_scopes('超級管理員')[0])
        # 有一個壞的就整個拒絕，不是只收好的那幾個。
        self.assertIsNone(g.parse_scopes('1,壞')[0])


class Claims(unittest.TestCase):
    def test_授權保留其他claim(self):
        out = g.claims_for_grant({'vip': True, 'admin': True, 'adminScopes': ['contentReview']},
                                 ['productManage'])
        self.assertEqual(out, {'vip': True, 'admin': True, 'adminScopes': ['productManage']})

    def test_全選不寫adminScopes_與舊腳本一致(self):
        out = g.claims_for_grant(None, list(g.SCOPE_KEYS))
        self.assertEqual(out, {'admin': True})

    def test_全選順序不同也算全選(self):
        out = g.claims_for_grant({}, ['platformConfig', 'contentReview', 'productManage'])
        self.assertNotIn('adminScopes', out)

    def test_部分權限組有adminScopes(self):
        out = g.claims_for_grant({}, ['contentReview'])
        self.assertEqual(out, {'admin': True, 'adminScopes': ['contentReview']})

    def test_收回只拿掉admin相關(self):
        self.assertEqual(g.claims_after_revoke({'admin': True, 'adminScopes': ['x'], 'vip': 1}),
                         {'vip': 1})

    def test_收回後沒有其他claim_回None(self):
        self.assertIsNone(g.claims_after_revoke({'admin': True}))
        self.assertIsNone(g.claims_after_revoke(None))

    def test_不改傳進來的dict(self):
        src = {'admin': True, 'vip': 1}
        g.claims_after_revoke(src)
        g.claims_for_grant(src, ['contentReview'])
        self.assertEqual(src, {'admin': True, 'vip': 1})


class LastAdmin(unittest.TestCase):
    def test_最後一位不能收回(self):
        self.assertTrue(g.would_remove_last_admin({'u1'}, 'u1'))

    def test_還有別人就可以(self):
        self.assertFalse(g.would_remove_last_admin({'u1', 'u2'}, 'u1'))

    def test_對方本來就不是管理員(self):
        self.assertFalse(g.would_remove_last_admin({'u1'}, 'u9'))


class Describe(unittest.TestCase):
    def test_中文說明與英文名稱並列(self):
        self.assertEqual(g.describe_scopes(['contentReview', 'platformConfig']),
                         '內容審核（contentReview）、平台設定（platformConfig）')

    def test_權限組與舊腳本同名(self):
        self.assertEqual(g.SCOPE_KEYS, g.base.SCOPES)


if __name__ == '__main__':
    unittest.main(verbosity=2)
