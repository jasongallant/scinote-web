<template>
  <div class="task-protocol">
    <div class="task-section-header" v-if="!inRepository">
      <div class="portocol-header-left-part">
        <a class="task-section-caret" tabindex="0" role="button" data-toggle="collapse" href="#protocol-content" aria-expanded="true" aria-controls="protocol-content">
          <i class="fas fa-caret-right"></i>
          <div class="task-section-title">
            <h2>{{ i18n.t('Protocol') }}</h2>
          </div>
        </a>
        <div class="my-module-protocol-status">
          <!-- protocol status dropdown gets mounted here -->
        </div>
      </div>
      <div class="actions-block">
        <div class="protocol-buttons-group">
          <a v-if="urls.add_step_url"
             class="btn btn-primary"
             @keyup.enter="addStep(steps.length)"
             @click="addStep(steps.length)"
             tabindex="0">
              <span class="fas fa-plus" aria-hidden="true"></span>
              <span>{{ i18n.t("protocols.steps.new_step") }}</span>
          </a>
          <button class="btn btn-secondary" data-toggle="modal" data-target="#print-protocol-modal" tabindex="0">
            <span class="fas fa-print" aria-hidden="true"></span>
            <span>{{ i18n.t("protocols.print.button") }}</span>
          </button>
          <ProtocolOptions
            v-if="protocol.attributes && protocol.attributes.urls"
            :protocol="protocol"
            @protocol:delete_steps="deleteSteps"
            :canDeleteSteps="steps.length > 0 && urls.delete_steps_url !== null"
          />
        </div>
      </div>
    </div>
    <div v-if="protocol.id" id="protocol-content" class="protocol-content collapse in" aria-expanded="true">
      <div class="protocol-description">
        <div class="protocol-name">
          <InlineEdit
            v-if="urls.update_protocol_name_url"
            :value="protocol.attributes.name"
            :characterLimit="255"
            :placeholder="i18n.t('my_modules.protocols.protocol_status_bar.enter_name')"
            :allowBlank="!inRepository"
            :attributeName="`${i18n.t('Protocol')} ${i18n.t('name')}`"
            @update="updateName"
          />
          <span v-else>
            {{ protocol.attributes.name }}
          </span>
        </div>
        <ProtocolMetadata v-if="protocol.attributes && protocol.attributes.in_repository" :protocol="protocol" @update="updateProtocol"/>
        <div v-if="urls.update_protocol_description_url">
          <Tinymce
            :value="protocol.attributes.description"
            :value_html="protocol.attributes.description_view"
            :placeholder="i18n.t('my_modules.protocols.protocol_status_bar.empty_description_edit_label')"
            :updateUrl="urls.update_protocol_description_url"
            :objectType="'Protocol'"
            :objectId="parseInt(protocol.id)"
            :fieldName="'protocol[description]'"
            :lastUpdated="protocol.attributes.updated_at"
            :characterLimit="100000"
            @update="updateDescription"
          />
        </div>
        <div v-else-if="protocol.attributes.description_view" v-html="protocol.attributes.description_view"></div>
        <div v-else class="empty-protocol-description">
          {{ i18n.t("protocols.no_text_placeholder") }}
        </div>
      </div>
      <a v-if="urls.add_step_url && protocol.attributes.in_repository" class="btn btn-primary repository-new-step"
          @keyup.enter="addStep(steps.length)" @click="addStep(steps.length)" tabindex="0">
        <span class="fas fa-plus" aria-hidden="true"></span>
        <span>{{ i18n.t("protocols.steps.new_step") }}</span>
      </a>
      <div v-if="steps.length > 0" class="protocol-step-actions">
        <button class="btn btn-light" @click="collapseSteps" tabindex="0">
          <span class="fas fa-caret-up"></span>
          {{ i18n.t("protocols.steps.collapse_label") }}
        </button>
        <button class="btn btn-light" @click="expandSteps" tabindex="0">
          <span class="fas fa-caret-down"></span>
          {{ i18n.t("protocols.steps.expand_label") }}
        </button>
        <a v-if="urls.reorder_steps_url"
           class="btn btn-light"
           data-toggle="modal"
           @click="startStepReorder"
           @keyup.enter="startStepReorder"
           :class="{'disabled': steps.length == 1}"
           tabindex="0" >
            <i class="fas fas-rotated-90 fa-exchange-alt" aria-hidden="true"></i>
            <span>{{ i18n.t("protocols.reorder_steps.button") }}</span>
        </a>
      </div>
      <div class="protocol-steps">
        <template v-for="(step, index) in steps">
          <div class="step-block" :key="step.id">
            <div v-if="index > 0 && urls.add_step_url" class="insert-step" @click="addStep(index)">
              <i class="fas fa-plus"></i>
            </div>
            <Step
              :step.sync="steps[index]"
              @reorder="startStepReorder"
              :inRepository="inRepository"
              @step:delete="updateStepsPosition"
              @step:update="updateStep"
              @stepUpdated="refreshProtocolStatus"
              @step:insert="updateStepsPosition"
              :reorderStepUrl="steps.length > 1 ? urls.reorder_steps_url : null"
            />
          </div>
        </template>
      </div>
      <button v-if="steps.length > 0 && urls.add_step_url" class="btn btn-primary" @click="addStep(steps.length)">
        <i class="fas fa-plus"></i>
        {{ i18n.t("protocols.steps.new_step") }}
      </button>
    </div>
    <ProtocolModals/>
    <ReorderableItemsModal v-if="reordering"
      :title="i18n.t('protocols.reorder_steps.modal.title')"
      :items="steps"
      :includeNumbers="true"
      @reorder="updateStepOrder"
      @close="closeStepReorderModal"
    />
  </div>
</template>

 <script>
  import InlineEdit from 'vue/shared/inline_edit.vue'
  import Step from 'vue/protocol/step'
  import ProtocolMetadata from 'vue/protocol/protocolMetadata'
  import ProtocolOptions from 'vue/protocol/protocolOptions'
  import ProtocolModals from 'vue/protocol/modals'
  import Tinymce from 'vue/shared/tinymce.vue'
  import ReorderableItemsModal from 'vue/protocol/modals/reorderable_items_modal.vue'

  import UtilsMixin from 'vue/mixins/utils.js'

  export default {
    name: 'ProtocolContainer',
    props: {
      protocolUrl: {
        type: String,
        required: true
      }
    },
    components: { Step, InlineEdit, ProtocolModals, ProtocolOptions, Tinymce, ReorderableItemsModal, ProtocolMetadata },
    mixins: [UtilsMixin],
    computed: {
      inRepository() {
        return this.protocol.attributes.in_repository
      },
      urls() {
        return this.protocol.attributes.urls || {}
      }
    },
    data() {
      return {
        protocol: {
          attributes: {}
        },
        steps: [],
        reordering: false
      }
    },
    created() {
      $.get(this.protocolUrl, (result) => {
        this.protocol = result.data;
        $.get(this.urls.steps_url, (result) => {
          this.steps = result.data
        })
      });
    },
    methods: {
      collapseSteps() {
        $('.step-container .collapse').collapse('hide')
      },
      expandSteps() {
        $('.step-container .collapse').collapse('show')
      },
      deleteSteps() {
        $.post(this.urls.delete_steps_url, () => {
          this.steps = []
        }).error(() => {
          HelperModule.flashAlertMsg(this.i18n.t('errors.general'), 'danger')
        })
      },
      refreshProtocolStatus() {
        if (this.inRepository) return
        // legacy method from app/assets/javascripts/my_modules/protocols.js
        refreshProtocolStatusBar();
      },
      updateProtocol(attributes) {
        this.protocol.attributes = attributes
      },
      updateName(newName) {
        this.protocol.attributes.name = newName;
        this.refreshProtocolStatus();
        $.ajax({
          type: 'PATCH',
          url: this.urls.update_protocol_name_url,
          data: { protocol: { name: newName } }
        });
      },
      updateDescription(protocol) {
        this.protocol.attributes = protocol.attributes
      },
      addStep(position) {
        $.post(this.urls.add_step_url, {position: position}, (result) => {
          result.data.newStep = true
          this.updateStepsPosition(result.data);

          // scroll to bottom if step was appended at the end
          if(position === this.steps.length - 1) {
            this.$nextTick(() => this.scrollToBottom());
          }
        })
        this.refreshProtocolStatus();
      },
      updateStepsPosition(step, action = 'add') {
        let position = step.attributes.position;
        if (action === 'delete') {
          this.steps.splice(position, 1)
        }
        let unordered_steps = this.steps.map( s => {
          if (s.attributes.position >= position) {
            if (action === 'add') {
              s.attributes.position += 1;
            } else {
              s.attributes.position -= 1;
            }
          }
          return s;
        })
        if (action === 'add') {
          unordered_steps.push(step);
        }
        this.reorderSteps(unordered_steps)
      },
      updateStep(attributes) {
        this.steps[attributes.position].attributes = {
          ...this.steps[attributes.position].attributes,
          ...attributes
        };
        this.refreshProtocolStatus();
      },
      reorderSteps(steps) {
        this.steps = steps.sort((a, b) => a.attributes.position - b.attributes.position);
        this.refreshProtocolStatus();
      },
      updateStepOrder(orderedSteps) {
        orderedSteps.forEach((step, position) => {
          let index = this.steps.findIndex((e) => e.id === step.id);
          this.steps[index].attributes.position = position;
        });

        let stepPositions =
          {
            step_positions: this.steps.map(
              (step) => [step.id, step.attributes.position]
            )
          };

        $.ajax({
          type: "POST",
          url: this.protocol.attributes.urls.reorder_steps_url,
          data: JSON.stringify(stepPositions),
          contentType: "application/json",
          dataType: "json",
          error: (() => HelperModule.flashAlertMsg(this.i18n.t('errors.general'), 'danger')),
          success: (() => this.reorderSteps(this.steps))
        });
      },
      startStepReorder() {
        this.reordering = true;
      },
      closeStepReorderModal() {
        this.reordering = false;
      },
      scrollToBottom() {
        window.scrollTo(0, document.body.scrollHeight);
      }
    }
  }
 </script>
