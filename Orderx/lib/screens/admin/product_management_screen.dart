import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:Orderx/models/product_model.dart';
import 'package:Orderx/services/product_service.dart';
import 'package:Orderx/services/image_service.dart';
import 'package:Orderx/providers/auth_provider.dart';
import 'package:Orderx/widgets/app_bar_actions.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  final ProductService _service = ProductService();
  final ImageService _imageService = ImageService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ProductModel> _products = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  String _searchQuery = '';
  Timer? _debounceTimer;
  int _totalProductCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _refreshProducts();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMore && _searchQuery.isEmpty) {
        _loadMoreProducts();
      }
    }
  }

  Future<void> _refreshProducts() async {
    setState(() {
      _products = [];
      _currentPage = 0;
      _hasMore = true;
      _isLoading = true;
      _totalProductCount = 0;
    });

    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;
    final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;
    
    try {
      final products = await _service.getProductsPaginated(
        companyId: effectiveCompanyId,
        page: 0,
        limit: 1000,
      );

      final totalCount = await _service.getTotalProductCount(companyId: effectiveCompanyId);

      if (mounted) {
        setState(() {
          _products = products;
          _hasMore = products.length >= 1000;
          _totalProductCount = totalCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final companyId = authProvider.selectedCompanyId;
      final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;

      final nextPage = _currentPage + 1;
      final newProducts = await _service.getProductsPaginated(
        companyId: effectiveCompanyId,
        page: nextPage,
        limit: 1000,
      );

      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _products.addAll(newProducts);
          _hasMore = newProducts.length >= 1000;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() => _searchQuery = '');
      _refreshProducts();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _searchProducts(query);
    });
  }

  Future<void> _searchProducts(String query) async {
    if (!mounted) return;

    setState(() {
      _searchQuery = query;
      _isLoading = true;
    });

    final authProvider = context.read<AuthProvider>();
    final companyId = authProvider.selectedCompanyId;
    final effectiveCompanyId = (companyId == 'ALL') ? null : companyId;
    
    try {
      final results = await _service.searchProducts(query, companyId: effectiveCompanyId);
      if (mounted) {
        setState(() {
          _products = results;
          _hasMore = false;
          _totalProductCount = results.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showAddProductDialog() async {
    await _showProductFormDialog(
      title: 'Add New Product',
      onSave: (product, selectedImage) async {
        try {
          final exists =
              await _service.productCodeExists(product.productCode ?? '');
          if (exists) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Product code already exists!')),
              );
            }
            return;
          }

          final productId = await _service.addProduct(
            productName: product.productName,
            productCode: product.productCode ?? '',
            unit: product.unit,
            price: product.price,
            gstRate: product.gstRate,
            isActive: product.isActive,
          );

          if (selectedImage != null && productId != null) {
            final imageInfo = await _imageService.uploadProductImage(
              selectedImage,
              productId,
            );

            if (imageInfo != null) {
              await _service.updateProductImage(
                productId,
                imageInfo['url']!,
                imageInfo['path']!,
              );
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Product added successfully!')),
            );
            _refreshProducts();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}')),
            );
          }
        }
      },
    );
  }

  Future<void> _showEditProductDialog(ProductModel product) async {
    await _showProductFormDialog(
      title: 'Edit Product',
      product: product,
      onSave: (updatedProduct, selectedImage) async {
        try {
          final exists = await _service.productCodeExists(
            updatedProduct.productCode ?? '',
            excludeId: product.id,
          );
          if (exists) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Product code already exists!')),
              );
            }
            return;
          }

          await _service.updateProduct(
            id: product.id,
            productName: updatedProduct.productName,
            productCode: updatedProduct.productCode ?? '',
            unit: updatedProduct.unit,
            price: updatedProduct.price,
            gstRate: updatedProduct.gstRate,
            isActive: updatedProduct.isActive,
          );

          if (selectedImage != null) {
            // Upload new image first; only delete old image after successful upload
            final imageInfo = await _imageService.uploadProductImage(
              selectedImage,
              product.id,
            );

            if (imageInfo != null) {
              if (product.imagePath != null) {
                await _imageService.deleteProductImage(product.imagePath!);
              }

              await _service.updateProductImage(
                product.id,
                imageInfo['url']!,
                imageInfo['path']!,
              );
            }
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Product updated successfully!')),
            );
            _refreshProducts();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}')),
            );
          }
        }
      },
    );
  }

  Future<void> _deleteProduct(ProductModel product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text(
            'Are you sure you want to delete "${product.productName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (product.imagePath != null) {
          await _imageService.deleteProductImage(product.imagePath!);
        }

        await _service.deleteProduct(product.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product deleted!')),
          );
          _refreshProducts();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting product: $e')),
          );
        }
      }
    }
  }

  Future<void> _showProductFormDialog({
    required String title,
    ProductModel? product,
    required Future<void> Function(ProductModel product, File? selectedImage)
        onSave,
  }) async {
    final nameController =
        TextEditingController(text: product?.productName ?? '');
    final codeController =
        TextEditingController(text: product?.productCode ?? '');
    final unitController = TextEditingController(text: product?.unit ?? 'PCS');
    final priceController =
        TextEditingController(text: product?.price.toString() ?? '0.0');
    final gstController =
        TextEditingController(text: product?.gstRate.toString() ?? '0.0');
    bool isActive = product?.isActive ?? true;
    bool isSaving = false;
    File? selectedImage;
    bool removeExistingImage = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Image Section
                      Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: selectedImage != null
                            ? Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      selectedImage!,
                                      width: double.infinity,
                                      height: 150,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: GestureDetector(
                                      onTap: () =>
                                          setState(() => selectedImage = null),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : product?.imageUrl != null && !removeExistingImage
                                ? Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          product!.imageUrl!,
                                          width: double.infinity,
                                          height: 150,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.grey.shade200,
                                              child: const Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(Icons.broken_image,
                                                      size: 40,
                                                      color: Colors.red),
                                                  Text('Failed to load image',
                                                      style: TextStyle(
                                                          fontSize: 12)),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      Positioned(
                                        top: 8,
                                        right: 8,
                                        child: GestureDetector(
                                          onTap: () => setState(
                                              () => removeExistingImage = true),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.red,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : GestureDetector(
                                    onTap: () async {
                                      try {
                                        final image = await _imageService
                                            .pickAndCompressImage();
                                        if (image != null) {
                                          setState(() {
                                            selectedImage = image;
                                            removeExistingImage = false;
                                          });
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Image picker not available in web browser'),
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.camera_alt,
                                            size: 40, color: Colors.grey),
                                        Text('Tap to add product image'),
                                      ],
                                    ),
                                  ),
                      ),
                      const SizedBox(height: 16),

                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Product Name *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeController,
                        decoration: const InputDecoration(
                          labelText: 'Product Code *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: unitController,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: priceController,
                              decoration: const InputDecoration(
                                labelText: 'Price *',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: gstController,
                              decoration: const InputDecoration(
                                labelText: 'GST Rate (%)',
                                border: OutlineInputBorder(),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              const Text('Active'),
                              Switch(
                                value: isActive,
                                onChanged: (value) =>
                                    setState(() => isActive = value),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final code = codeController.text.trim();
                          if (name.isEmpty || code.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Name and code required')),
                            );
                            return;
                          }

                          final price =
                              double.tryParse(priceController.text) ?? 0.0;
                          final gst =
                              double.tryParse(gstController.text) ?? 0.0;

                          setState(() => isSaving = true);
                          try {
                            final productData = ProductModel(
                              id: product?.id ?? '',
                              productName: name,
                              productCode: code,
                              unit: unitController.text.isNotEmpty
                                  ? unitController.text
                                  : 'PCS',
                              price: price,
                              gstRate: gst,
                              isActive: isActive,
                              createdAt: product?.createdAt,
                              updatedAt: DateTime.now(),
                              imageUrl: product?.imageUrl,
                              imagePath: product?.imagePath,
                            );

                            if (removeExistingImage &&
                                product?.imagePath != null) {
                              await _imageService
                                  .deleteProductImage(product!.imagePath!);
                              await _service.removeProductImage(product.id);
                            }

                            await onSave(productData, selectedImage);
                            if (mounted) Navigator.pop(context);
                          } finally {
                            if (mounted) setState(() => isSaving = false);
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Management'),
        actions: [
          GlobalCompanySwitcher(onCompanyChanged: _refreshProducts),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshProducts,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or code...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$_totalProductCount Products Found',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          if (!_isLoading)
            const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? const Center(child: Text('No products found'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _products.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _products.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final product = _products[index];
                          final stockText = product.stock % 1 == 0
                              ? product.stock.toInt().toString()
                              : product.stock.toStringAsFixed(2);
                          final hasStock = product.stock > 0;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 2),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Product Image
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          color: Colors.grey.shade200,
                                        ),
                                        child: product.imageUrl != null
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Image.network(
                                                  product.imageUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const Icon(
                                                          Icons.inventory_2,
                                                          color: Colors.grey),
                                                ),
                                              )
                                            : const Icon(Icons.inventory_2,
                                                color: Colors.grey),
                                      ),
                                      const SizedBox(width: 12),
                                      // Product Name, Code & Stock Badge
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product.productName,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 6,
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                if (product.productCode !=
                                                        null &&
                                                    product.productCode!
                                                        .trim()
                                                        .isNotEmpty)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade100,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                      border: Border.all(
                                                          color: Colors
                                                              .grey.shade300),
                                                    ),
                                                    child: Text(
                                                      product.productCode!
                                                          .trim(),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey.shade700,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                // Stock Badge
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2.5),
                                                  decoration: BoxDecoration(
                                                    color: hasStock
                                                        ? Colors.green.shade50
                                                        : Colors.red.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                    border: Border.all(
                                                      color: hasStock
                                                          ? Colors
                                                              .green.shade300
                                                          : Colors
                                                              .red.shade300,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        hasStock
                                                            ? Icons
                                                                .check_circle_outline
                                                            : Icons
                                                                .remove_circle_outline,
                                                        size: 13,
                                                        color: hasStock
                                                            ? Colors
                                                                .green.shade700
                                                            : Colors
                                                                .red.shade700,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Stock: $stockText ${product.unit}',
                                                        style: TextStyle(
                                                          fontSize: 11.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: hasStock
                                                              ? Colors
                                                                  .green.shade800
                                                              : Colors
                                                                  .red.shade800,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Actions
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit,
                                                size: 20),
                                            tooltip: 'Edit',
                                            onPressed: () =>
                                                _showEditProductDialog(product),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: Colors.red, size: 20),
                                            tooltip: 'Delete',
                                            onPressed: () =>
                                                _deleteProduct(product),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  // Price Levels Section
                                  const SizedBox(height: 10),
                                  const Divider(height: 1, thickness: 0.5),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          'Price Levels: ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: product.priceLevels.isNotEmpty
                                            ? Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: product.priceLevels
                                                    .map((slab) {
                                                  return Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.blue.shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      border: Border.all(
                                                          color: Colors
                                                              .blue.shade200),
                                                    ),
                                                    child: Text(
                                                      slab.displayLabel,
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors
                                                            .blue.shade900,
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              )
                                            : (product.price > 0
                                                ? Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade100,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      border: Border.all(
                                                          color: Colors
                                                              .grey.shade300),
                                                    ),
                                                    child: Text(
                                                      'Standard: ₹${product.price.toStringAsFixed(2)} / ${product.unit}',
                                                      style: TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Colors
                                                            .grey.shade800,
                                                      ),
                                                    ),
                                                  )
                                                : Text(
                                                    'No price level defined',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                      color:
                                                          Colors.grey.shade500,
                                                    ),
                                                  )),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      // floatingActionButton: Provider.of<AuthProvider>(context).selectedCompanyId == 'ALL'
      //     ? FloatingActionButton(
      //         onPressed: () {
      //           ScaffoldMessenger.of(context).showSnackBar(
      //             const SnackBar(content: Text('Please select a specific company to add products')),
      //           );
      //         },
      //         backgroundColor: Colors.grey,
      //         child: const Icon(Icons.add, color: Colors.white),
      //       )
      //     : FloatingActionButton(
      //         onPressed: _showAddProductDialog,
      //         backgroundColor: AppTheme.primaryBlue,
      //         child: const Icon(Icons.add, color: Colors.white),
      //       ),
    );
  }
}
