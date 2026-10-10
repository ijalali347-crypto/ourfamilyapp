import 'package:flutter_test/flutter_test.dart';
import 'package:our_family_app/chat_directory.dart';

void main() {
  test('both people compute the same shared conversation ID', () {
    expect(directChatId('alice', 'bob'), directChatId('bob', 'alice'));
  });
  test('different user pairs do not collide across separators', () {
    expect(directChatId('a_b', 'c'), isNot(directChatId('a', 'b_c')));
    expect(directChatId('a.b', 'c'), isNot(directChatId('a', 'b.c')));
  });
  test('same-account devices cannot accidentally create a self call', () {
    expect(() => directChatId('alice', 'alice'), throwsArgumentError);
  });
}
