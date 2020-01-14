// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * A collection of utility methods used by completion contributors.
 */
import 'package:analysis_server/src/protocol_server.dart'
    show CompletionSuggestion, CompletionSuggestionKind, Location;
import 'package:analysis_server/src/provisional/completion/dart/completion_dart.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/standard_ast_factory.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/ast/token.dart';
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart' as protocol
    show Element, ElementKind;

/**
 * The name of the type `dynamic`;
 */
const DYNAMIC = 'dynamic';

/**
 * A marker used in place of `null` when a function has no return type.
 */
final TypeName NO_RETURN_TYPE = astFactory.typeName(
    astFactory.simpleIdentifier(StringToken(TokenType.IDENTIFIER, '', 0)),
    null);

/**
 * Add default argument list text and ranges based on the given [requiredParams]
 * and [namedParams].
 */
void addDefaultArgDetails(
    CompletionSuggestion suggestion,
    Element element,
    Iterable<ParameterElement> requiredParams,
    Iterable<ParameterElement> namedParams) {
  StringBuffer sb = StringBuffer();
  List<int> ranges = <int>[];

  int offset;

  for (ParameterElement param in requiredParams) {
    if (sb.isNotEmpty) {
      sb.write(', ');
    }
    offset = sb.length;
    String name = param.name;
    sb.write(name);
    ranges.addAll([offset, name.length]);
  }

  for (ParameterElement param in namedParams) {
    if (param.hasRequired) {
      if (sb.isNotEmpty) {
        sb.write(', ');
      }
      String name = param.name;
      sb.write('$name: ');
      offset = sb.length;
      String defaultValue = _getDefaultValue(param);
      sb.write(defaultValue);
      ranges.addAll([offset, defaultValue.length]);
    }
  }

  suggestion.defaultArgumentListString = sb.isNotEmpty ? sb.toString() : null;
  suggestion.defaultArgumentListTextRanges = ranges.isNotEmpty ? ranges : null;
}

/**
 * Create a new protocol Element for inclusion in a completion suggestion.
 */
protocol.Element createLocalElement(
    Source source, protocol.ElementKind kind, SimpleIdentifier id,
    {String parameters,
    TypeAnnotation returnType,
    bool isAbstract = false,
    bool isDeprecated = false}) {
  String name;
  Location location;
  if (id != null) {
    name = id.name;
    // TODO(danrubel) use lineInfo to determine startLine and startColumn
    location = Location(source.fullName, id.offset, id.length, 0, 0);
  } else {
    name = '';
    location = Location(source.fullName, -1, 0, 1, 0);
  }
  int flags = protocol.Element.makeFlags(
      isAbstract: isAbstract,
      isDeprecated: isDeprecated,
      isPrivate: Identifier.isPrivateName(name));
  return protocol.Element(kind, name, flags,
      location: location,
      parameters: parameters,
      returnType: nameForType(id, returnType));
}

/**
 * Sort by relevance first, highest to lowest, and then by the completion
 * alphabetically.
 */
Comparator<CompletionSuggestion> completionComparator = (sug1, sug2) {
  if (sug1.relevance == sug2.relevance) {
    return sug1.completion.compareTo(sug2.completion);
  }
  return sug2.relevance.compareTo(sug1.relevance);
};

/**
 * Create a new suggestion based upon the given information. Return the new
 * suggestion or `null` if it could not be created.
 */
CompletionSuggestion createLocalSuggestion(SimpleIdentifier id,
    bool isDeprecated, int defaultRelevance, TypeAnnotation returnType,
    {ClassOrMixinDeclaration classDecl,
    CompletionSuggestionKind kind = CompletionSuggestionKind.INVOCATION,
    protocol.Element element}) {
  if (id == null) {
    return null;
  }
  String completion = id.name;
  if (completion == null || completion.isEmpty || completion == '_') {
    return null;
  }
  CompletionSuggestion suggestion = CompletionSuggestion(
      kind,
      isDeprecated ? DART_RELEVANCE_LOW : defaultRelevance,
      completion,
      completion.length,
      0,
      isDeprecated,
      false,
      returnType: nameForType(id, returnType),
      element: element);
  if (classDecl != null) {
    SimpleIdentifier classId = classDecl.name;
    if (classId != null) {
      String className = classId.name;
      if (className != null && className.isNotEmpty) {
        suggestion.declaringType = className;
      }
    }
  }
  return suggestion;
}

DefaultArgument getDefaultStringParameterValue(ParameterElement param) {
  if (param != null) {
    DartType type = param.type;
    if (type is InterfaceType && type.isDartCoreList) {
      String getTypeArgumentsStr() {
        var elementType = type.typeArguments.single;
        if (elementType.isDynamic) {
          return '';
        } else {
          var typeArgStr = elementType.getDisplayString(
            withNullability: false,
          );
          return '<$typeArgStr>';
        }
      }

      String typeArgumentStr = getTypeArgumentsStr();
      String text = '$typeArgumentStr[]';
      return DefaultArgument(text, cursorPosition: text.length - 1);
    } else if (type is FunctionType) {
      String params = type.parameters
          .map((p) => '${getTypeString(p.type)}${p.name}')
          .join(', ');
      // TODO(devoncarew): Support having this method return text with newlines.
      String text = '($params) {  }';
      return DefaultArgument(text, cursorPosition: text.length - 2);
    }

    // TODO(pq): support map literals

  }

  return null;
}

String getTypeString(DartType type) {
  if (type.isDynamic) {
    return '';
  } else {
    return type.getDisplayString(withNullability: false) + ' ';
  }
}

/**
 * Return `true` if the @deprecated annotation is present on the given [node].
 */
bool isDeprecated(AnnotatedNode node) {
  if (node != null) {
    NodeList<Annotation> metadata = node.metadata;
    if (metadata != null) {
      return metadata.any((Annotation a) {
        return a.name is SimpleIdentifier && a.name.name == 'deprecated';
      });
    }
  }
  return false;
}

/**
 * Return name of the type of the given [identifier], or, if it unresolved, the
 * name of its declared [declaredType].
 */
String nameForType(SimpleIdentifier identifier, TypeAnnotation declaredType) {
  if (identifier == null) {
    return null;
  }

  // Get the type from the identifier element.
  DartType type;
  Element element = identifier.staticElement;
  if (element == null) {
    return DYNAMIC;
  } else if (element is FunctionTypedElement) {
    if (element is PropertyAccessorElement && element.isSetter) {
      return null;
    }
    type = element.returnType;
  } else if (element is FunctionTypeAliasElement) {
    type = element.function.returnType;
  } else if (element is VariableElement) {
    type = element.type;
  } else {
    return null;
  }

  // If the type is unresolved, use the declared type.
  if (type != null && type.isDynamic) {
    if (declaredType is TypeName) {
      Identifier id = declaredType.name;
      if (id != null) {
        return id.name;
      }
    }
    return DYNAMIC;
  }

  if (type == null) {
    return DYNAMIC;
  }
  return type.toString();
}

// TODO(pq): fix to use getDefaultStringParameterValue()
String _getDefaultValue(ParameterElement param) => 'null';

/**
 * A tuple of text to insert and an (optional) location for the cursor.
 */
class DefaultArgument {
  /**
   * The text to insert.
   */
  final String text;

  /**
   * An optional location for the cursor, relative to the text's start. This
   * field can be null.
   */
  final int cursorPosition;

  DefaultArgument(this.text, {this.cursorPosition});
}
