<template>
  <div ref="modal" class="modal fade" id="modal-print-repository-row-label" tabindex="-1" role="dialog" aria-labelledby="myModalLabel">
    <div class="modal-dialog" role="document">
      <div class="modal-content">
        <div v-if="availablePrinters.length > 0" class="printers-available">
          <div class="modal-header">
            <button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            <p class="modal-title">
              <template v-if="rows.length == 1">
                <b>{{ i18n.t('repository_row.modal_print_label.head_title', {repository_row: rows[0].attributes.name}) }}</b>
                <span class="id-label">
                  {{ i18n.t('repository_row.modal_print_label.id_label', {repository_row_id: rows[0].attributes.code}) }}
                </span>
              </template>
              <template v-else>
                <b>{{ i18n.t('repository_row.modal_print_label.head_title_multiple', {repository_rows: rows.length}) }}</b>
              </template>
            </p>
          </div>
          <div class="modal-body">
            <div class=printers-container>
              <label>
                {{ i18n.t('repository_row.modal_print_label.printer') }}
              </label>
              <DropdownSelector
                :disableSearch="true"
                :options="availablePrinters"
                :selectorId="`LabelPrinterSelector`"
                @dropdown:changed="selectPrinter"
              />
            </div>

            <div class=labels-container>
              <label>
                {{ i18n.t('repository_row.modal_print_label.label') }}
              </label>

              <DropdownSelector
                ref="labelTemplateDropdown"
                :disableSearch="true"
                :options="availableTemplates"
                :selectorId="`LabelTemplateSelector`"
                :optionLabel="templateOption"
                :onOpen="initTooltip"
                @dropdown:changed="selectTemplate"
              />
              <div v-if="labelTemplateError" class="label-template-warning">
                {{ labelTemplateError }}
              </div>
            </div>
            <p class="sci-input-container">
              <label>
                {{ i18n.t('repository_row.modal_print_label.number_of_copies') }}
              </label>
              <input v-model="copies" type=number class="sci-input-field print-copies-input" min="1">
            </p>
            <div class="label-preview-title">
              {{ i18n.t('repository_row.modal_print_label.label_preview') }}
            </div>
            <div class="label-preview-container">
              <LabelPreview v-if="labelTemplateCode" :zpl='labelTemplateCode' :template="selectedTemplate" :previewUrl="urls.labelPreview" :viewOnly="true"/>
            </div>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-default" data-dismiss="modal"> {{ i18n.t('general.cancel') }}</button>
            <button class="btn btn-primary" @click="submitPrint">
              {{ i18n.t(`repository_row.modal_print_label.${labelTemplateError ? 'print_anyway' : 'print_label'}`) }}
            </button>
          </div>
        </div>
        <div v-else class="no-printers-available">
          <div class="modal-body no-printers-container">
            <button type="button" class="close modal-absolute-close-button" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>
            <img src='/images/printers/no_available_printers.png'>
            <p class="no-printer-title">
              {{ i18n.t('repository_row.modal_print_label.no_printers.title') }}
            </p>
            <p class="no-printer-body">
              {{ i18n.t('repository_row.modal_print_label.no_printers.description') }}
            </p>
          </div>
          <div class="modal-footer">
            <a :href="urls.fluicsInfo" target="blank" class="btn btn-primary" >
              {{ i18n.t('repository_row.modal_print_label.no_printers.visit_blog') }}
            </a>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
  import DropdownSelector from 'vue/shared/dropdown_selector.vue'
  import LabelPreview from 'vue/label_template/components/label_preview.vue'

  export default {
    name: 'PrintModalContainer',
    props: {
      showModal: Boolean,
      row_ids: Array,
      urls: Object,
      zebraEnabled: Boolean
    },
    data() {
      return {
        rows: [],
        printers: [],
        templates: [],
        selectedPrinter: null,
        selectedTemplate: null,
        copies: 1,
        zebraPrinters: null,
        labelTemplateError: null,
        labelTemplateCode: null
      }
    },
    components: {
      DropdownSelector,
      LabelPreview
    },
    mounted() {
      $.get(this.urls.labelTemplates, (result) => {
        this.templates = result.data
        this.selectDefaultLabelTemplate();
      })

      $.get(this.urls.printers, (result) => {
        this.printers = result.data
      })

      $(this.$refs.modal).on('hidden.bs.modal', () => {
        this.$emit('close');
      });

      if (this.zebraEnabled) {
        this.initZebraPrinter();
      }
    },
    computed: {
      availableTemplates() {
        let templates = this.templates;
        if (this.selectedPrinter && this.selectedPrinter.attributes.type_of === 'zebra') {
          templates = templates.filter(i => i.attributes.type === 'ZebraLabelTemplate')
        }

        return templates.map(i => {
          return {
            value: i.id,
            label: i.attributes.name,
            params: {
              icon: i.attributes.icon_url,
              description: i.attributes.description || ''
            }
          }
        })
      },
      availablePrinters() {
        return this.printers.map(i => {
          return {
            value: i.id,
            label: i.attributes.display_name
          }
        })
      }
    },
    watch: {
      showModal() {
        if (this.showModal) {
          $(this.$refs.modal).modal('show');
          this.validateTemplate();
        }
      },
      row_ids() {
        $.get(this.urls.rows, {rows: this.row_ids}, (result) => {
          this.rows = result.data
        })
      }
    },
    methods: {
      selectDefaultLabelTemplate() {
        if (this.selectedPrinter && this.templates) {
          let template = this.templates.find(i => i.attributes.default
            && i.type.includes(this.selectedPrinter.attributes.type_of));
          if (template) {
            this.$nextTick(() => {
              this.$refs.labelTemplateDropdown.selectValues(template.id);
            });
          }
        }
      },
      selectPrinter(value) {
        this.selectedPrinter = this.printers.find(i => i.id === value)
        this.selectDefaultLabelTemplate();
      },
      selectTemplate(value) {
        this.selectedTemplate = this.templates.find(i => i.id === value);
        this.validateTemplate();
      },
      validateTemplate() {
        if (!this.selectedTemplate || this.row_ids.length == 0) return;

        $.post(this.urls.printValidation, {label_template_id: this.selectedTemplate.id, rows: this.row_ids}, (result) => {
          this.labelTemplateError = null;
          this.labelTemplateCode = result.label_code;
        }).error((result) => {
          this.labelTemplateError = result.responseJSON.error;
          this.labelTemplateCode = result.responseJSON.label_code;
        })
      },
      submitPrint() {
        this.$nextTick(() => {
          if (this.selectedPrinter.attributes.type_of === 'zebra') {
            this.zebraPrinters.print(
              this.urls.zebraProgress,
              '.label-printing-progress-modal',
              '#modal-print-repository-row-label',
              {
                printer_name: this.selectedPrinter.attributes.name,
                number_of_copies: this.copies,
                label_template_id: this.selectedTemplate.id,
                rows: this.row_ids
              }
            );
          } else {
            $.post(this.urls.print, {
              rows: this.row_ids,
              label_printer_id: this.selectedPrinter.id,
              label_template_id: this.selectedTemplate.id,
              copies: this.copies
            }, (data) => {
              $(this.$refs.modal).modal('hide');
              this.$emit('close');
              PrintProgressModal.init(data);
            })
          }
        });
      },
      initZebraPrinter() {
        this.zebraPrinters = zebraPrint.init($('#LabelPrinterSelector'), {
          clearSelectorOnFirstDevice: false,
          appendDevice: (device) => {
            this.printers.push({
              id: `zebra${this.printers.length}`,
              attributes: {
                name: device.name,
                display_name: device.name,
                type_of: 'zebra'
              }
            })
          }
        }, false);
      },
      templateOption(option) {
        return `
          <div class="label-template-option" data-toggle="tooltip" data-placement="right" title="${option.params.description}">
            <img src="${option.params.icon}"></img>
            ${option.label}
          </div>
        `
      },
      initTooltip() {
        $('[data-toggle="tooltip"]').tooltip();
      }
    }
  }
</script>
